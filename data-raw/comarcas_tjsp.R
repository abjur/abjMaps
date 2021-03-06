# lista os codigos de todos os municipios --------------------------------------
get_all_muni <- function() {
  u_muni <- "http://www.tjsp.jus.br/AutoComplete/ListarMunicipios"
  all_muni <- abjData::dados_muni %>% 
    dplyr::filter(uf == "SP") %>% 
    dplyr::pull(municipio) %>% 
    stringr::str_to_upper() %>% 
    abjutils::rm_accent() %>% 
    stringr::str_replace_all("'", " ") %>%
    stringr::str_replace_all("MOJI", "MOGI") %>%
    stringr::str_replace_all(" D .+", "") %>% 
    dplyr::if_else(
      str_detect(., "^SANTA|^SAO"), ., stringr::str_extract(., "[A-Z]+")
    ) %>%
    unique() %>% 
    sort() %>% 
    c("SAO", "SANTA")
}

get_muni_codes <- function() {
  all_muni <- get_all_muni()
  all_muni %T>% 
    {.p <<- progress::progress_bar$new(total = length(.))} %>% 
    purrr::map_dfr(~{
    r1 <- httr::POST(u_muni, body = list(texto = .x))
    .p$tick()
    httr::content(r1, "parsed") %>% 
      purrr::map_dfr(tibble::as_tibble) %>% 
      dplyr::mutate(query = .x) %>% 
      janitor::clean_names()
    }) %>% 
    distinct(codigo, .keep_all = TRUE)
}
# all_muni_tjsp <- get_muni_codes()
# readr::write_rds(all_muni_tjsp, "all_muni_tjsp.rds")
all_muni_tjsp <- readr::read_rds("all_muni_tjsp.rds")

# pega textos das comarcas -----------------------------------------------------
get_comarca_text <- function(cod_municipio) {
  u_resultado <- "http://www.tjsp.jus.br/ListaTelefonica/RetornarResultadoBusca"
  .p <- progress::progress_bar$new(total = length(cod_municipio))
  purrr::map_chr(cod_municipio, ~{
    bd <- list(parmsEntrada = .x, codigoTipoBusca = "1")
    r0 <- httr::POST(u_resultado, body = bd)
    .p$tick()
    h4 <- r0 %>% 
      httr::content("parsed") %>% 
      rvest::html_nodes("h4") %>% 
      rvest::html_text()
    if (length(h4) == 0) "comarca" else h4[1]
  })
}
# muni_com_comarca_raw <- all_muni_tjsp %>% 
#   dplyr::arrange(codigo) %>% 
#   dplyr::mutate(txt_comarca = get_comarca_text(codigo))
# 
# readr::write_rds(muni_com_comarca_raw, "muni_com_comarca_raw.rds")
muni_com_comarca_raw <- readr::read_rds("muni_com_comarca_raw.rds")

# arrumar nomes das comarcas ---------------------------------------------------
arrumar_nomes_comarcas <- function(muni_com_comarca_raw) {
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
# muni_com_comarca <- muni_com_comarca_raw %>% 
#   arrumar_nomes_comarcas()
# readr::write_rds(muni_com_comarca, "muni_com_comarca.rds")
muni_com_comarca <- readr::read_rds("muni_com_comarca.rds")

# bater com comarcas do prodTJSP -----------------------------------------------
court <- prodTJSP::courts
comarcas_lista_telefonica <- muni_com_comarca %>% 
  dplyr::distinct(comarca) %>% 
  dplyr::mutate(comarca = comarca %>% 
           stringr::str_to_upper() %>% 
           abjutils::rm_accent() %>% 
           stringr::str_replace_all("'", " ")) %>% 
  dplyr::mutate(comarca = dplyr::case_when(
    comarca == "BRODOWSKI" ~ "BRODOSQUI",
    comarca == "ESTRELA DOESTE" ~ "ESTRELA D OESTE",
    comarca == "IPAUSSU" ~ "IPAUCU",
    comarca == "MOGI GUACU" ~ "MOJI GUACU",
    comarca == "PARIQUERA-ACU" ~ "PARIQUERA ACU",
    comarca == "SAO PAULO" ~ "CENTRAL",
    TRUE ~ comarca
  ))

comarcas_prod <- count(court, id_comarca, comarca = nm_comarca) %>% 
  dplyr::mutate(comarca = dplyr::case_when(
    comarca == "BRAS CUBAS", "MOGI DAS CRUZES"
  ))

anti_join(comarcas_lista_telefonica, comarcas_prod)
anti_join(comarcas_prod, comarcas_lista_telefonica)

# listar imoveis ---------------------------------------------------------------
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
  .p <- progress::progress_bar$new(total = length(cod_municipio))
  cod_municipio %>% 
    purrr::set_names(.) %>% 
    purrr::map_dfr(~{
      cod <- as.character(.x)
      r0 <- httr::GET(u_imoveis, query = list(codigo = cod))
      # r0 %>% scrapr::html_view()
      .p$tick()
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
# imoveis_list <- muni_com_comarca %>% 
#   dplyr::pull(cod_municipio) %>% 
#   get_imoveis()
# 
# readr::write_rds(imoveis_list, "imoveis_list.rds")
imoveis_list <- readr::read_rds("imoveis_list.rds")

# carregar infos imoveis -------------------------------------------------------
# parse imoveis ----------------------------------------------------------------
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

# download imoveis -------------------------------------------------------------
download_imoveis <- function(cod_imovel) {
  u_imovel <- "http://www.tjsp.jus.br/ListaTelefonica/ObterImovel"
  .p <- progress::progress_bar$new(total = length(cod_imovel))
  cod_imovel %>% 
    purrr::set_names(.) %>% 
    purrr::map_dfr(~{
    r <- httr::POST(u_imovel, body = list(codigo = .x))
    # scrapr::html_view(r)
    .p$tick()
    httr::content(r, "parsed") %>% 
      parse_imovel()
  }, .id = "cod_imovel")
}
# imoveis_raw <- imoveis_list %>% 
#   dplyr::distinct(cod_imovel) %>% 
#   dplyr::pull(cod_imovel) %>% 
#   download_imoveis()
# readr::write_rds(imoveis_raw, "imoveis_raw.rds")
imoveis_raw <- readr::read_rds("imoveis_raw.rds")

# tidy imoveis -----------------------------------------------------------------
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
# imoveis_tidy <- tidy_imoveis(imoveis_raw)
# readr::write_rds(imoveis_tidy, "imoveis_tidy.rds")
imoveis_tidy <- readr::read_rds("imoveis_tidy.rds")

# regioes administrativas ------------------------------------------------------
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
                        sep = " [-–] ") %>% 
        dplyr::mutate(regiao = nm)
    }) %>% 
    tidyr::separate(regiao, c("num_regiao", "regiao"), sep = " [-–] ") %>% 
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
# regioes <- get_adm_regions()
# readr::write_rds(regioes, "regioes.rds")
regioes <- readr::read_rds("regioes.rds")


# complementando infos de todas as bases ---------------------------------------
completar_comarcas <- function(imoveis_tidy, imoveis_list, muni_com_comarca) {
  imoveis_aux <- imoveis_list %>% 
    dplyr::mutate(cod_imovel = as.character(cod_imovel)) %>% 
    dplyr::inner_join(imoveis_tidy, "cod_imovel") %>% 
    dplyr::select(cod_municipio, circunscricao = circunscricao_judiciaria,
                  entrancia) %>% 
    # a unica entrancia nao informada é SP
    dplyr::mutate(entrancia = dplyr::if_else(entrancia == "Não Informado", 
                                             "Entrância Final", entrancia)) %>% 
    dplyr::mutate(cod_municipio = as.integer(cod_municipio)) %>% 
    dplyr::distinct(cod_municipio, .keep_all = TRUE)
  muni_com_comarca %>% 
    dplyr::inner_join(imoveis_aux, "cod_municipio") %>% 
    dplyr::inner_join(regioes, "comarca") %>% 
    dplyr::arrange(comarca, tipo)
}
# muni_comarcas_completo <- completar_comarcas(imoveis_tidy, imoveis_list,
#                                              muni_com_comarca)
# readr::write_rds(muni_comarcas_completo, "muni_comarcas_completo.rds")
muni_comarcas_completo <- readr::read_rds("muni_comarcas_completo.rds")


# shapefiles -------------------------------------------------------------------

## origin: ftp://geoftp.ibge.gov.br/organizacao_do_territorio/
##         malhas_territoriais/malhas_municipais/municipio_2015/UFs/SP/
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
    unzip("shp/sp.zip", exdir = "shp/")
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
# d_sf <- build_sf(muni_comarcas_completo)
# readr::write_rds(d_sf, "d_sf.rds", compress = "xz")
d_sf <- readr::read_rds("d_sf.rds")

# mapas ------------------------------------------------------------------------
p_somado <- d_sf_municipio %>% 
  ggplot() +
  # needs ggplot dev version
  geom_sf(aes(fill = tipo), size = 0) +
  geom_sf(aes(fill = NULL), data = d_sf_comarca, 
          fill = "transparent", colour = "gray20", size = .3) +
  geom_sf(aes(fill = NULL), data = d_sf_circunscricao, 
          fill = "transparent", colour = "black", size = 1) +
  theme_minimal()

p_list <- purrr::map(d_sf$sf, ~{
  ggplot(.x) +
    geom_sf() +
    theme_minimal()})

gridExtra::grid.arrange(grobs = p_list, ncol = 2)

p_comarca <- d_sf$sf$comarca %>% 
  mutate(entrancia = lvls_reorder(entrancia, c(2, 3, 1))) %>% 
  ggplot() +
  geom_sf(aes(fill = entrancia)) +
  scale_fill_brewer() +
  theme_minimal()


