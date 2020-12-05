#' Shapefile TJSP
#'
#' Base contendo os shapefiles de municipios, comarcas,
#' regioes e circunscricoes do TJSP.
#'
#' @format A data frame with 4 rows and 2 variables:
#' \describe{
#'   \item{nivel}{nivel da regiao (municipio, comarca, circunscricao, regiao)}
#'   \item{sf}{shape, num objeto do tipo simple feature}
#' }
#' @source \url{http://www.tjsp.jus.br/ListaTelefonica}
"d_sf_tjsp"

#' Shapefile TJRS
#'
#' Base contendo os shapefiles de municipios e comarcas do TJRS.
#'
#' @format A data frame with 2 rows and 2 variables:
#' \describe{
#'   \item{nivel}{nivel da regiao (municipio, comarca)}
#'   \item{sf}{shape, num objeto do tipo simple feature}
#' }
#' @source \url{http://www.tjrs.jus.br/institu/comarcas/}
"d_sf_tjrs"
