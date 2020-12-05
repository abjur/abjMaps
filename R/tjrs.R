tjrs_comarcas <- function() {
  u <- "http://www.tjrs.jus.br/institu/comarcas/"
  r <- httr::GET(u)
  comarcas <- httr::content(r, "text") %>%
    stringr::str_match_all("(?<=\"Comarca de )([^\"]+)\",\"([0-9]+)") %>%
    dplyr::first() %>%
    tibble::as_tibble() %>%
    dplyr::select(comarca = V2, cod = V3)
}

tjrs_muni <- function(cod, verbose = FALSE) {
  if (verbose) message(cod)
  u <- "http://www.tjrs.jus.br/institu/comarcas/dados_comarca.php?codigo="
  u <- paste0(u, cod)
  r <- httr::GET(u)
  res <- r %>%
    xml2::read_html() %>%
    xml2::xml_find_all("//span[@class='texto_geral']") %>%
    purrr::map(xml2::xml_text) %>%
    purrr::map(stringr::str_trim)
  entrancia <- res[[2]] %>%
    stringr::str_extract("(?<=: ).*")
  municipios <- stringr::str_split(res[[1]], "\r\n") %>%
    unlist()
  tibble::tibble(municipio = municipios,
                 entrancia = entrancia) %>%
    tidyr::separate(municipio, c("municipio", "sede"),
                    sep = " - ",
                    extra = "merge", fill = "right") %>%
    dplyr::mutate_all(stringr::str_squish)
}

tjrs_comarca_muni <- function() {
  tjrs_comarcas() %>%
    dplyr::mutate(data = purrr::map(cod, tjrs_muni)) %>%
    tidyr::unnest(data) %>%
    dplyr::mutate(
      municipio = toupper(municipio),
      municipio = dplyr::case_when(
        municipio == "SANTANA DO LIVRAMENTO" ~ "SANT'ANA DO LIVRAMENTO",
        municipio == "WESTF\u00c1LIA" ~ "WESTFALIA",
        municipio == "SANTA CECILIA DO SUL" ~ "SANTA CEC\u00cdLIA DO SUL",
        municipio == "CHIAPETA" ~ "CHIAPETTA",
        TRUE ~ municipio
      )
    )
}

build_sf_tjrs <- function(muni_comarcas_completo) {
  if (!file.exists("shp")) {
    dir.create("shp", showWarnings = FALSE)
    u_ibge <- paste0(
      "ftp://geoftp.ibge.gov.br/organizacao_do_territorio/",
      "malhas_territoriais/malhas_municipais/",
      "municipio_2015/UFs/RS/rs_municipios.zip",
      collapse = "")
    message("Downloading shapefiles...")
    httr::GET(u_ibge,
              httr::write_disk("shp/rs.zip"),
              httr::progress())
    unzip("shp/rs.zip", exdir = "shp/")
  }
  # carregar shp municipios
  d_sf_municipio <- "shp/43MUE250GC_SIR.shp" %>%
    sf::st_read(quiet = TRUE) %>%
    janitor::clean_names() %>%
    dplyr::mutate(municipio = as.character(nm_municip)) %>%
    dplyr::inner_join(muni_comarcas_completo, "municipio")
  # join das comarcas
  d_sf_comarca <- d_sf_municipio %>%
    dplyr::group_by(comarca) %>%
    dplyr::summarise(entrancia = dplyr::first(entrancia)) %>%
    dplyr::ungroup()
  # final
  tibble::tibble(
    nivel = c("municipio", "comarca"),
    sf = list(municipio = d_sf_municipio, comarca = d_sf_comarca)
  )
}
