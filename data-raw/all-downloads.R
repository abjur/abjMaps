library(tidyverse)
devtools::load_all()

# gets all muni codes ----------------------------------------------------------
all_muni_tjsp <- get_muni_codes()
readr::write_rds(all_muni_tjsp, "data-raw/all_muni_tjsp.rds")
all_muni_tjsp <- readr::read_rds("data-raw/all_muni_tjsp.rds")

# pega textos das comarcas -----------------------------------------------------
muni_com_comarca_raw <- all_muni_tjsp %>%
  dplyr::arrange(codigo) %>%
  dplyr::mutate(txt_comarca = get_comarca_text(codigo))

readr::write_rds(muni_com_comarca_raw, "data-raw/muni_com_comarca_raw.rds")
muni_com_comarca_raw <- readr::read_rds("data-raw/muni_com_comarca_raw.rds")

# arrumar nomes das comarcas ---------------------------------------------------
muni_com_comarca <- muni_com_comarca_raw %>%
  clean_comarcas_names()

readr::write_rds(muni_com_comarca, "data-raw/muni_com_comarca.rds")
muni_com_comarca <- readr::read_rds("data-raw/muni_com_comarca.rds")

# listar imoveis ---------------------------------------------------------------
imoveis_list <- muni_com_comarca %>%
  dplyr::pull(cod_municipio) %>%
  get_imoveis()

readr::write_rds(imoveis_list, "data-raw/imoveis_list.rds")
imoveis_list <- readr::read_rds("data-raw/imoveis_list.rds")

# carregar infos imoveis -------------------------------------------------------
# parse imoveis ----------------------------------------------------------------
# download imoveis -------------------------------------------------------------
imoveis_raw <- imoveis_list %>%
  dplyr::distinct(cod_imovel) %>%
  dplyr::pull(cod_imovel) %>%
  download_imoveis()

readr::write_rds(imoveis_raw, "data-raw/imoveis_raw.rds")
imoveis_raw <- readr::read_rds("data-raw/imoveis_raw.rds")

# tidy imoveis -----------------------------------------------------------------
imoveis_tidy <- tidy_imoveis(imoveis_raw)
readr::write_rds(imoveis_tidy, "data-raw/imoveis_tidy.rds")
imoveis_tidy <- readr::read_rds("data-raw/imoveis_tidy.rds")

# regioes administrativas ------------------------------------------------------
regioes <- get_adm_regions()
readr::write_rds(regioes, "data-raw/regioes.rds")
regioes <- readr::read_rds("data-raw/regioes.rds")

# complementando infos de todas as bases ---------------------------------------
muni_comarcas_completo <- completar_comarcas(
  imoveis_tidy, imoveis_list, muni_com_comarca)
readr::write_rds(muni_comarcas_completo, "data-raw/muni_comarcas_completo.rds")
muni_comarcas_completo <- readr::read_rds("data-raw/muni_comarcas_completo.rds")

# shapefiles -------------------------------------------------------------------
## origin: ftp://geoftp.ibge.gov.br/organizacao_do_territorio/
##         malhas_territoriais/malhas_municipais/municipio_2015/UFs/SP/
d_sf <- build_sf(muni_comarcas_completo)
readr::write_rds(d_sf, "data-raw/d_sf.rds", compress = "xz")
d_sf <- readr::read_rds("data-raw/d_sf.rds")


