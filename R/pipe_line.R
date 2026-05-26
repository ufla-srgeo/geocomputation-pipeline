# ==============================================================================
# PIPELINE DE PROCESSAMENTO GEOSPACIAL E ANÁLISE GEOMORFOMÉTRICA
# Projeto: Doutorado UFLA - 2026
# ==============================================================================

# 1. DEFINIÇÃO DE DIRETÓRIOS E CONFIGURAÇÃO INICIAL ---------------------------
# Caminho de referência solicitado
dir_base <- "/home/vitor/compartilhada/UFLA/doutorado/2026_01/Sensoriamento_remoto_geoprocessamento/template_latex/git_hub/"

if (!dir.exists(dir_base)) dir.create(dir_base, recursive = TRUE)
setwd(dir_base)

# Criar subpasta para organizar os outputs caso não exista
if (!dir.exists("bonsucesso")) dir.create("bonsucesso")

# 2. CARREGAMENTO DOS PACOTES --------------------------------------------------
library(geobr)
library(sf)
library(ggplot2)
library(geodata)
library(terra)
library(rgeomorphon)

# 3. EXTRAÇÃO E EXPORTAÇÃO DE DADOS VETORIAIS (geobr) -------------------------
message("--- Etapa 1: Baixando e processando dados vetoriais (geobr) ---")

# Estado de Minas Gerais
mg <- read_state(code_state = "MG", year = 2017, showProgress = FALSE)

# Município de Bom Sucesso
bs <- read_municipality(code_muni = 3108008, year = 2017, showProgress = FALSE)

# Todos os municípios do estado de Minas Gerais
muni <- read_municipality(code_muni = "MG", year = 2017, showProgress = FALSE)

# Exportar polígonos como ESRI Shapefile usando caminhos relativos ao setwd()
st_write(mg, dsn = "bonsucesso/mg.shp", delete_layer = TRUE, quiet = TRUE)
st_write(bs, dsn = "bonsucesso/bs.shp", delete_layer = TRUE, quiet = TRUE)
st_write(muni, dsn = "bonsucesso/muni.shp", delete_layer = TRUE, quiet = TRUE)

# 4. PROCESSAMENTO DO MODELO DIGITAL DE ELEVAÇÃO (terra + geodata) ------------
message("--- Etapa 2: Obtendo e processando dados de altitude (SRTM) ---")

# Ler o vetor salvo anteriormente via pacote terra (SpComposite)
bs_v <- vect("bonsucesso/bs.shp")

# Obter dados de altitude (SRTM 3s) utilizando as coordenadas da região
alt <- elevation_3s(lon = -44.979, lat = -21.18141, path = tempdir())

# Reprojetar o polígono do município para WGS-84 (compatível com o dado do geodata)
bs_wgs84 <- project(bs_v, "EPSG:4326")

# Recortar e mascarar o relevo para os limites exatos do município
bs_e <- crop(alt, bs_wgs84, mask = TRUE)

# Exportar MDE recortado e o vetor reprojetado
writeRaster(bs_e, filename = "bonsucesso/bs_e.tif", overwrite = TRUE)
writeVector(bs_wgs84, "bonsucesso/bs_wgs.shp", overwrite = TRUE)

# 5. ANÁLISE GEOMORFOMÉTRICA (rgeomorphon) -----------------------------------
message("--- Etapa 3: Classificação do relevo por Geomorphons ---")

# Garantir que o DEM seja lido como tipo real (floating point)
dem_real <- bs_e * 1 

# Reprojetar o Raster e o Vetor para Sistema de Coordenadas Planas (UTM 23S - SIRGAS 2000)
# Essencial para que os parâmetros de distância ('search', 'skip') funcionem em metros
dem_prj <- project(dem_real, "EPSG:32723", method = "bilinear", res = 90)
bs_prj  <- project(bs_wgs84, "EPSG:32723")

# Rodar diferentes cenários/modelos de Geomorphons
geo   <- geomorphons(elevation = dem_prj, search = 7,  skip = 1, dist = 0, flat = 1, comparison_mode = "anglev1")
geo01 <- geomorphons(elevation = dem_prj, search = 7,  skip = 1, dist = 0, flat = 1, comparison_mode = "anglev2")
geo02 <- geomorphons(elevation = dem_prj, search = 7,  skip = 1, dist = 0, flat = 1, comparison_mode = "anglev2_distance")
geo60 <- geomorphons(elevation = dem_prj, search = 60, skip = 1, dist = 0, flat = 1, comparison_mode = "anglev2_distance")
geod  <- geomorphons(elevation = dem_prj) # Parâmetros padrão

# Exportar os Rasters gerados de maior interesse
writeRaster(dem_prj, filename = "bonsucesso/dem_prj.tif", overwrite = TRUE)
writeRaster(geo,     filename = "bonsucesso/geo.tif",     overwrite = TRUE)
writeVector(bs_prj,  "bonsucesso/bs_prj.shp",             overwrite = TRUE)

# 6. CÁLCULO DE ÁREA DAS CLASSES ----------------------------------------------
message("--- Etapa 4: Extraindo estatísticas de área (Hectares) ---")

areas_geo   <- expanse(geo,   byValue = TRUE, unit = "ha")
areas_geo1  <- expanse(geo01, byValue = TRUE, unit = "ha")
areas_geo2  <- expanse(geo02, byValue = TRUE, unit = "ha")
areas_geo60 <- expanse(geo60, byValue = TRUE, unit = "ha")
areas_geod  <- expanse(geod,  byValue = TRUE, unit = "ha")

# 7. COMPILAÇÃO E VISUALIZAÇÃO GRÁFICA (ggplot2) -----------------------------
message("--- Etapa 5: Gerando gráficos comparativos ---")

# Adicionar tags de identificação para cada cenário
areas_geo$analise  <- "Geo (Search 7 - anglev1)"
areas_geo1$analise <- "Geo01 (Search 7 - anglev2)"
areas_geo2$analise <- "Geo02 (Search 7 - anglev2_dist)"

# Combinar os data.frames verticalmente
areas_combined <- rbind(areas_geo, areas_geo1, areas_geo2)

# Ajustando nomes das colunas vindas da função `expanse` (geralmente: layer, value, area)
colnames(areas_combined) <- c("layer", "classe", "area_ha", "analise")

# Gerar gráfico facetado comparando os 3 principais métodos
grafico_comparativo <- ggplot(areas_combined, aes(x = reorder(factor(classe), area_ha), y = area_ha, fill = factor(classe))) +
  geom_col() +
  coord_flip() +  
  facet_wrap(~analise, scales = "free_x") + 
  labs(
    title = "Comparação de Área por Classe de Relevo em Bom Sucesso/MG",
    subtitle = "Análise baseada em diferentes parametrizações do rgeomorphon",
    x = "Classe Numérica do Relevo", 
    y = "Área (Hectares)"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",
    strip.text = element_text(face = "bold", size = 10)
  )

# Salvar o gráfico gerado na pasta de resultados
ggsave("bonsucesso/comparacao_areas_geomorphons.png", plot = grafico_comparativo, width = 12, height = 6, dpi = 300)

message("--- PIPELINE CONCLUÍDO COM SUCESSO! ---")
