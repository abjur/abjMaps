library(abjMaps)

d_sf_tjrs$sf <- purrr::map(d_sf_tjrs$sf, ~{
  .x %>%
    tibble::as_tibble() %>%
    sf::st_as_sf()
})

usethis::use_data(d_sf_tjrs, overwrite = TRUE, compress = "xz")

d_sf_tjsp <- d_sf

d_sf_tjsp$sf <- purrr::map(d_sf_tjsp$sf, ~{
  .x %>%
    tibble::as_tibble() %>%
    sf::st_as_sf()
})

usethis::use_data(d_sf_tjsp, compress = "xz")
