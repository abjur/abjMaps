#' Downloads all municipalities
#'
#' Downloads all municipalities from Lista Telefonica data - TJSP
#'
#' @return \code{character} vector with all 645 cleaned municipalities
#'
#' @export
get_all_muni <- function() {
  u_muni <- "http://www.tjsp.jus.br/AutoComplete/ListarMunicipios"
  abjData::dados_muni %>%
    dplyr::filter(uf == "SP") %>%
    dplyr::pull(municipio) %>%
    stringr::str_to_upper() %>%
    abjutils::rm_accent() %>%
    stringr::str_replace_all("'", " ") %>%
    stringr::str_replace_all("MOJI", "MOGI") %>%
    stringr::str_replace_all(" D .+", "") %>%
    dplyr::if_else(
      stringr::str_detect(., "^SANTA|^SAO"), .,
      stringr::str_extract(., "[A-Z]+")
    ) %>%
    unique() %>%
    sort() %>%
    c("SAO", "SANTA")
}

#' Downloads the codes for all the municipalities
#'
#' Downloads all municipalities codes from Lista Telefonica data - TJSP
#'
#' @return \code{character} vector with all 645 cleaned municipalities
#'
#' @export
get_muni_codes <- function() {
  all_muni <- get_all_muni()
  u_muni <- "http://www.tjsp.jus.br/AutoComplete/ListarMunicipios"
  all_muni %>%
    purrr::map_dfr(~{
      r1 <- httr::POST(u_muni, body = list(texto = .x))
      httr::content(r1, "parsed") %>%
        purrr::map_dfr(tibble::as_tibble) %>%
        dplyr::mutate(query = .x) %>%
        janitor::clean_names()
    }) %>%
    dplyr::distinct(codigo, .keep_all = TRUE)
}

#' Gets comarca text
#'
#' Gets comarca text from municipality code to tell whether the municipality is
#' a comarca or just a part of the comarca.
#'
#' @param cod_municipio code
#'
#' @return returns a phrase if it is a municipality and "comarca" if it is a comarca
#'
#' @export
get_comarca_text <- function(cod_municipio) {
  u_resultado <- "http://www.tjsp.jus.br/ListaTelefonica/RetornarResultadoBusca"
  purrr::map_chr(cod_municipio, ~{
    bd <- list(parmsEntrada = .x, codigoTipoBusca = "1")
    r0 <- httr::POST(u_resultado, body = bd)
    h4 <- r0 %>%
      httr::content("parsed") %>%
      rvest::html_nodes("h4") %>%
      rvest::html_text()
    if (length(h4) == 0) "comarca" else h4[1]
  })
}

#' Cleans comarca names
#'
#' Cleans comarca names from \code{get_comarca_text} function.
#'
#' @param muni_com_comarca_raw object returned from \code{get_comarca_text} fun
#'
#' @return data frame
#'
#' @export
clean_comarcas_names <- function(muni_com_comarca_raw) {
  muni_com_comarca_raw %>%
    dplyr::mutate(
      tipo = dplyr::if_else(txt_comarca == "comarca", "comarca", "municipio"),
      comarca = dplyr::case_when(
        tipo == "comarca" ~ descricao,
        TRUE ~ str_extract(txt_comarca, "(?<=comarca ).+$"))) %>%
    dplyr::arrange(comarca) %>%
    dplyr::select(cod_municipio = codigo,
                  comarca,
                  municipio = descricao,
                  tipo) %>%
    dplyr::arrange(comarca, cod_municipio)  %>%
    dplyr::mutate(municipio = municipio %>%
                    stringr::str_to_upper() %>%
                    abjutils::rm_accent() %>%
                    stringr::str_replace_all("DOESTE", "D'OESTE")) %>%
    dplyr::mutate(comarca = abjutils::rm_accent(toupper(comarca)))
}

parse_imovel_result_info <- function(html) {
  title <- html %>%
    rvest::html_node(".col-md-9") %>%
    rvest::html_nodes("span") %>%
    rvest::html_text()
  cod <- html %>%
    rvest::html_node(".col-md-9") %>%
    rvest::html_nodes("a") %>%
    rvest::html_attr("data-codigo")
  tibble::tibble(imovel_title = title, cod_imovel = cod)
}

get_imoveis <- function(cod_municipio) {
  u_imoveis <- "http://www.tjsp.jus.br/ListaTelefonica/ObterImoveisPorMunicipio"
  cod_municipio %>%
    purrr::set_names(.) %>%
    purrr::map_dfr(~{
      cod <- as.character(.x)
      r0 <- httr::GET(u_imoveis, query = list(codigo = cod))
      # r0 %>% scrapr::html_view()
      html <- httr::content(r0, "parsed")
      npag <- html %>%
        rvest::html_nodes(".pages") %>%
        rvest::html_text() %>%
        purrr::pluck(1) %>%
        stringr::str_extract("[0-9]+$") %>%
        as.numeric()
      if (length(npag) == 0) npag <- 1
      result_p1 <- parse_imovel_result_info(html)
      if (npag > 1) {
        result_pags <- purrr::map_dfr(2:npag, ~{
          r <- httr::GET(u_imoveis, query = list(codigo = cod, pagina = .x))
          html_pag <- httr::content(r, "parsed")
          parse_imovel_result_info(html_pag)
        })
        return(dplyr::bind_rows(result_p1, result_pags))
      }
      result_p1
    }, .id = "cod_municipio") %>%
    dplyr::mutate(cod_imovel = as.numeric(cod_imovel)) %>%
    dplyr::arrange(cod_imovel)
}


parse_imovel_div <- function(div) {
  titulo <- div %>%
    rvest::html_node("h2") %>%
    rvest::html_text()
  key <- div %>%
    rvest::html_nodes("dt") %>%
    rvest::html_text() %>%
    stringr::str_trim()
  if (length(key) == 0) key <- ""
  val <- div %>%
    rvest::html_nodes("dd") %>%
    rvest::html_text() %>%
    stringr::str_trim()
  if (length(val) == 0) val <- ""
  tibble::tibble(titulo, key, val)
}

parse_imovel <- function(html) {
  nm <- html %>%
    rvest::html_node("#imovelNome") %>%
    rvest::html_text()
  html %>%
    rvest::html_nodes(".lista-dados") %>%
    purrr::map_dfr(parse_imovel_div)
}

download_imoveis <- function(cod_imovel) {
  u_imovel <- "http://www.tjsp.jus.br/ListaTelefonica/ObterImovel"
  cod_imovel %>%
    purrr::set_names(.) %>%
    purrr::map_dfr(~{
      r <- httr::POST(u_imovel, body = list(codigo = .x))
      # scrapr::html_view(r)
      httr::content(r, "parsed") %>%
        parse_imovel()
    }, .id = "cod_imovel")
}

tidy_imoveis <- function(imoveis_raw) {
  tidy_chunk <- function(.data) {
    .data %>%
      purrr::set_names(sprintf("%010d", seq_along(.))) %>%
      dplyr::bind_rows(.id = ".id") %>%
      dplyr::group_by(.id, key) %>%
      dplyr::summarise(val = glue::collapse(val, sep = "\n")) %>%
      dplyr::ungroup() %>%
      tidyr::spread(key, val) %>%
      purrr::set_names(abjutils::rm_accent) %>%
      purrr::set_names(stringr::str_replace_all, " de ", " ") %>%
      janitor::clean_names() %>%
      dplyr::group_by(`_id`) %>%
      tidyr::nest() %>%
      dplyr::pull(data)
  }
  imoveis_raw %>%
    dplyr::group_by(cod_imovel, titulo) %>%
    tidyr::nest() %>%
    tidyr::spread(titulo, data) %>%
    purrr::set_names(abjutils::rm_accent) %>%
    purrr::set_names(stringr::str_replace_all, " de ", " ") %>%
    janitor::clean_names() %>%
    purrr::map_at(c("contato_administrativo", "dados_gerais", "localizacao"),
                  tidy_chunk) %>%
    tibble::as_tibble() %>%
    tidyr::unnest(contato_administrativo, dados_gerais, localizacao)
}

get_adm_regions <- function() {
  u_regioes <- paste0(
    "http://www.tjsp.jus.br/QuemSomos/",
    "QuemSomos/RegioesAdministrativasJudiciarias",
    collapse = "")
  r <- httr::GET(u_regioes)
  r %>%
    httr::content("parsed") %>%
    rvest::html_nodes(".list-group") %>%
    purrr::map_dfr(~{
      nm <- .x %>%
        rvest::html_node(xpath = "./preceding-sibling::div[1]/p") %>%
        rvest::html_text() %>%
        stringr::str_trim()
      .x %>%
        rvest::html_nodes(".list-group-item") %>%
        rvest::html_text() %>%
        stringr::str_trim() %>%
        tibble::enframe() %>%
        tidyr::separate(value, c("comarca", "num_circunscricao"),
                        sep = " [-\u2013] ") %>%
        dplyr::mutate(regiao = nm)
    }) %>%
    tidyr::separate(regiao, c("num_regiao", "regiao"), sep = " [-\u2013] ") %>%
    dplyr::select(comarca, num_circunscricao, num_regiao, regiao) %>%
    dplyr::mutate(
      comarca = abjutils::rm_accent(stringr::str_to_upper(comarca)),
      comarca = dplyr::case_when(
        comarca == "RIO GRANDE DE SERRA" ~ "RIO GRANDE DA SERRA",
        comarca == "SANTANA DO PARNAIBA" ~ "SANTANA DE PARNAIBA",
        comarca == "SANTA ROSA DO VITERBO" ~ "SANTA ROSA DE VITERBO",
        comarca == "ESTRELA D'OESTE" ~ "ESTRELA DOESTE",
        comarca == "VILA MIMOSA" ~ NA_character_,
        comarca == "CARAQUATATUBA" ~ "CARAGUATATUBA",
        TRUE ~ comarca))
}

completar_comarcas <- function(imoveis_tidy, imoveis_list, muni_com_comarca) {
  imoveis_aux <- imoveis_list %>%
    dplyr::mutate(cod_imovel = as.character(cod_imovel)) %>%
    dplyr::inner_join(imoveis_tidy, "cod_imovel") %>%
    dplyr::select(cod_municipio, circunscricao = circunscricao_judiciaria,
                  entrancia) %>%
    # a unica entrancia nao informada é SP
    dplyr::mutate(entrancia = dplyr::if_else(entrancia == "N\u00e3o Informado",
                                             "Entr\u00e2ncia Final", entrancia)) %>%
    dplyr::mutate(cod_municipio = as.integer(cod_municipio)) %>%
    dplyr::distinct(cod_municipio, .keep_all = TRUE)
  muni_com_comarca %>%
    dplyr::inner_join(imoveis_aux, "cod_municipio") %>%
    dplyr::inner_join(regioes, "comarca") %>%
    dplyr::arrange(comarca, tipo)
}

build_sf <- function(muni_comarcas_completo) {
  if (!file.exists("shp")) {
    dir.create("shp", showWarnings = FALSE)
    u_ibge <- paste0(
      "ftp://geoftp.ibge.gov.br/organizacao_do_territorio/",
      "malhas_territoriais/malhas_municipais/",
      "municipio_2015/UFs/SP/sp_municipios.zip",
      collapse = "")
    message("Downloading shapefiles...")
    httr::GET(u_ibge, httr::write_disk("shp/sp.zip", overwrite = TRUE),
              httr::progress())
    utils::unzip("shp/sp.zip", exdir = "shp/")
  }
  # carregar shp municipios
  d_sf_municipio <- "shp/35MUE250GC_SIR.shp" %>%
    sf::st_read(quiet = TRUE) %>%
    janitor::clean_names() %>%
    dplyr::mutate(municipio = abjutils::rm_accent(nm_municip)) %>%
    dplyr::inner_join(muni_comarcas_completo, "municipio")
  # join das comarcas
  d_sf_comarca <- d_sf_municipio %>%
    dplyr::group_by(comarca) %>%
    dplyr::summarise(entrancia = dplyr::first(entrancia)) %>%
    dplyr::ungroup()
  # join das circunscricoes
  d_sf_circunscricao <- d_sf_municipio %>%
    dplyr::group_by(circunscricao) %>%
    dplyr::summarise() %>%
    dplyr::ungroup()
  # join das regioes
  d_sf_regiao <- d_sf_municipio %>%
    dplyr::group_by(regiao) %>%
    dplyr::summarise() %>%
    dplyr::ungroup()
  # final
  tibble::tibble(
    nivel = c("municipio", "comarca", "circunscricao", "regiao"),
    sf = list(municipio = d_sf_municipio, comarca = d_sf_comarca,
              circunscricao = d_sf_circunscricao, regiao = d_sf_regiao))
}



