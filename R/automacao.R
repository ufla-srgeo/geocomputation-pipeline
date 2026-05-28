# ==============================================================================
# SHINY APP — PIPELINE GEOMORFOMÉTRICO INTERATIVO
# Adaptado do pipeline de Doutorado UFLA - 2026 (Sensoriamento Remoto e Geo)
# Autor original: Vítor Augusto Ferreira / Narcelo de Carvalho Alves
# ==============================================================================
library(shiny)
library(geobr)
library(sf)
library(ggplot2)
library(geodata)
library(terra)
library(rgeomorphon)

# Cache
CACHE_DIR <- "cache_geo"
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR)

# Nomes e cores (agora com nomes textuais)
cores_nomeadas <- c(
  "Flat"      = "#FFFFC8",
  "Peak"      = "#8B0000",
  "Ridge"     = "#FF4500",
  "Shoulder"  = "#FF8C00",
  "Spur"      = "#FFD700",
  "Slope"     = "#9ACD32",
  "Hollow"    = "#228B22",
  "Footslope" = "#006400",
  "Valley"    = "#1E90FF",
  "Pit"       = "#00008B"
)

# -----------------------------------------------------------------------------
# Funções com cache
# -----------------------------------------------------------------------------
get_mde_cached <- function(cod_municipio) {
  cache_path <- file.path(CACHE_DIR, paste0("mde_", cod_municipio, ".tif"))
  if (file.exists(cache_path)) {
    return(rast(cache_path))
  }
  # Baixa e salva
  bs_sf <- read_municipality(code_muni = cod_municipio, year = 2017, showProgress = FALSE)
  bs_v <- vect(bs_sf)
  bs_wgs <- project(bs_v, "EPSG:4326")
  centro <- centroids(bs_wgs)
  lon_c <- crds(centro)[1, 1]
  lat_c <- crds(centro)[1, 2]
  alt <- elevation_3s(lon = lon_c, lat = lat_c, path = tempdir())
  bs_e <- crop(alt, bs_wgs, mask = TRUE)
  writeRaster(bs_e, cache_path, overwrite = TRUE)
  bs_e
}

get_geo_cached <- function(cod_municipio, resolucao, search, flat, modo) {
  chave <- paste(cod_municipio, resolucao, search, flat, modo, sep = "_")
  cache_path <- file.path(CACHE_DIR, paste0("geo_", chave, ".tif"))
  if (file.exists(cache_path)) {
    return(rast(cache_path))
  }
  
  dem <- get_mde_cached(cod_municipio)
  # Define resolução (em metros) conforme escolha do usuário
  res_m <- switch(resolucao,
                  "rapido"  = 270,
                  "medio"   = 180,
                  "completo" = 90)
  
  # Projeção para UTM (fuso 23S) – ajuste se necessário
  dem_prj <- project(dem, "EPSG:32723", method = "bilinear", res = res_m)
  
  geo <- geomorphons(
    elevation       = dem_prj,
    search          = search,
    skip            = 1,
    dist            = 0,
    flat            = flat,
    comparison_mode = modo
  )
  writeRaster(geo, cache_path, overwrite = TRUE)
  geo
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
ui <- fluidPage(
  
  tags$head(
    tags$style(HTML("
      body { background-color: #f5f5f5; font-family: 'Segoe UI', sans-serif; }
      .titulo-app { background-color: #2c3e50; color: white; padding: 18px 24px;
                    border-radius: 8px; margin-bottom: 20px; }
      .titulo-app h3 { margin: 0; font-size: 20px; }
      .titulo-app p  { margin: 4px 0 0 0; font-size: 13px; color: #bdc3c7; }
      .painel-lateral { background: white; border-radius: 8px;
                        padding: 16px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); }
      .painel-resultado { background: white; border-radius: 8px;
                          padding: 16px; box-shadow: 0 1px 4px rgba(0,0,0,0.1);
                          margin-bottom: 16px; }
      .btn-rodar { background-color: #27ae60; color: white; width: 100%;
                   font-weight: bold; border: none; padding: 10px;
                   border-radius: 6px; font-size: 15px; margin-top: 8px; }
      .btn-rodar:hover { background-color: #1e8449; color: white; }
      .btn-limpar { background-color: #e74c3c; color: white; width: 100%;
                    font-weight: bold; border: none; padding: 8px;
                    border-radius: 6px; font-size: 13px; margin-top: 6px; }
      .btn-limpar:hover { background-color: #c0392b; color: white; }
      .badge-cache { background: #3498db; color: white; border-radius: 10px;
                     padding: 2px 8px; font-size: 11px; }
      .badge-download { background: #e67e22; color: white; border-radius: 10px;
                        padding: 2px 8px; font-size: 11px; }
      .status-box { border-left: 4px solid #27ae60; padding: 8px 12px;
                    background: #eafaf1; border-radius: 4px; font-size: 13px; }
      .aviso-box  { border-left: 4px solid #f39c12; padding: 8px 12px;
                    background: #fef9e7; border-radius: 4px; font-size: 13px; }
      hr { border-color: #ecf0f1; }
    "))
  ),
  
  div(class = "titulo-app",
      h3("🌄 Pipeline Geomorfométrico Interativo"),
      p("Sensoriamento Remoto e Geoprocessamento open-source em R — UFLA Doutorado 2026")
  ),
  
  sidebarLayout(
    
    sidebarPanel(width = 3,
                 div(class = "painel-lateral",
                     
                     h4("📍 Município Alvo"),
                     numericInput("cod_municipio", "Geocódigo IBGE:",
                                  value = 3108008, min = 1000000, max = 9999999),
                     helpText("Ex: 3108008 = Bom Sucesso/MG"),
                     
                     hr(),
                     h4("🖥️ Performance"),
                     
                     radioButtons("resolucao", "Modo de resolução:",
                                  choices = c(
                                    "⚡ Rápido (270m — recomendado para PCs lentos)" = "rapido",
                                    "⚖️ Médio  (180m)"                               = "medio",
                                    "🔬 Completo (90m — SRTM original)"              = "completo"
                                  ),
                                  selected = "rapido"
                     ),
                     div(class = "aviso-box",
                         "💡 No modo Rápido o processamento é até ",
                         strong("5× mais veloz"), " com leve perda de detalhe."
                     ),
                     
                     hr(),
                     h4("⚙️ Parâmetros Geomorphons"),
                     
                     sliderInput("search", "Raio de busca (células):",
                                 min = 3, max = 60, value = 7, step = 1),
                     helpText("1 célula = resolução escolhida acima"),
                     
                     sliderInput("flat", "Limiar de planeza (graus):",
                                 min = 0.5, max = 5, value = 1, step = 0.5),
                     
                     selectInput("comparison_mode", "Modo de comparação:",
                                 choices  = c("anglev1", "anglev2", "anglev2_distance"),
                                 selected = "anglev1"),
                     
                     hr(),
                     h4("📊 Visualização"),
                     
                     selectInput("tipo_grafico", "Tipo de gráfico:",
                                 choices = c(
                                   "Barras por área (ha)"   = "barra",
                                   "Barras por porcentagem" = "pct",
                                   "Mapa do relevo"         = "mapa"
                                 )),
                     
                     hr(),
                     actionButton("rodar",   "▶  Executar Pipeline", class = "btn-rodar"),
                     actionButton("limpar",  "🗑️  Limpar Cache",      class = "btn-limpar"),
                     
                     br(), br(),
                     uiOutput("info_cache")
                 )
    ),
    
    mainPanel(width = 9,
              
              uiOutput("status_ui"),
              
              fluidRow(column(12,
                              div(class = "painel-resultado",
                                  h4("📈 Estatísticas do Modelo Digital de Elevação"),
                                  uiOutput("estatisticas_mde")
                              )
              )),
              
              fluidRow(column(12,
                              div(class = "painel-resultado",
                                  h4("🗺️ Resultado da Classificação"),
                                  plotOutput("grafico_principal", height = "420px")
                              )
              )),
              
              fluidRow(column(12,
                              div(class = "painel-resultado",
                                  h4("📋 Tabela de Distribuição por Classe"),
                                  tableOutput("tabela_areas")
                              )
              ))
    )
  )
)


# -----------------------------------------------------------------------------
# SERVER
# -----------------------------------------------------------------------------
server <- function(input, output, session) {
  
  resultado <- reactiveVal(NULL)
  
  observeEvent(input$rodar, {
    # Validação básica
    if (is.na(input$cod_municipio) || input$cod_municipio < 1000000) {
      showNotification("Geocódigo inválido!", type = "error")
      return()
    }
    
    showNotification("Processando... (pode levar alguns minutos)", type = "message", duration = NULL, id = "proc")
    
    tryCatch({
      # Executa pipeline (bloqueante, mas com cache fica mais rápido)
      geo <- get_geo_cached(input$cod_municipio,
                            input$resolucao,
                            input$search,
                            input$flat,
                            input$comparison_mode)
      
      # Áreas: expanse retorna data.frame com colunas: layer, value, area
      areas <- expanse(geo, byValue = TRUE, unit = "ha")
      names(areas) <- c("layer", "classe", "area_ha")  # renomeia
      
      # areas$area_ha já é numérico; areas$classe é texto (ex: "Flat", "Peak"...)
      areas$pct <- round(areas$area_ha / sum(areas$area_ha) * 100, 2)
      areas <- areas[order(-areas$area_ha), ]
      
      # Estatísticas do MDE (opcional)
      dem <- get_mde_cached(input$cod_municipio)
      vals <- values(dem, na.rm = TRUE)
      stats_mde <- list(
        min = round(min(vals), 1),
        max = round(max(vals), 1),
        media = round(mean(vals), 1),
        mediana = round(median(vals), 1)
      )
      
      resultado(list(areas = areas, geo = geo, stats = stats_mde, cod = input$cod_municipio))
      removeNotification("proc")
      showNotification("Concluído com sucesso!", type = "message")
    }, error = function(e) {
      removeNotification("proc")
      showNotification(paste("Erro:", e$message), type = "error", duration = 10)
    })
  })
  
  output$status_ui <- renderUI({
    req(resultado())
    div(class = "alert alert-success",
        paste0("✅ Município: ", resultado()$cod, " | Resolução: ", input$resolucao,
               " | Search: ", input$search, " | Modo: ", input$comparison_mode))
  })
  
  output$grafico_principal <- renderPlot({
    req(resultado())
    res <- resultado()
    df <- res$areas
    
    # Ordenar para gráfico de barras
    df$classe <- factor(df$classe, levels = rev(df$classe))
    
    if (input$tipo_grafico == "barra") {
      ggplot(df, aes(x = classe, y = area_ha, fill = classe)) +
        geom_col(show.legend = FALSE) +
        geom_text(aes(label = paste0(round(area_ha, 0), " ha")), hjust = -0.1, size = 3.5) +
        coord_flip() +
        scale_fill_manual(values = cores_nomeadas) +
        labs(title = "Área por classe geomórfica", y = "Hectares", x = NULL) +
        theme_minimal()
    } else if (input$tipo_grafico == "pct") {
      ggplot(df, aes(x = classe, y = pct, fill = classe)) +
        geom_col(show.legend = FALSE) +
        geom_text(aes(label = paste0(pct, "%")), hjust = -0.1, size = 3.5) +
        coord_flip() +
        scale_fill_manual(values = cores_nomeadas) +
        labs(title = "Porcentagem por classe", y = "%", x = NULL) +
        theme_minimal()
    } else {
      # Mapa
      par(mar = c(2, 2, 3, 5))
      plot(res$geo, col = cores_nomeadas, main = paste("Geomorphons -", res$cod), legend = TRUE)
      # Opcional: adicionar contorno do município (requer obter o vetor novamente)
    }
  })
  
  output$tabela_areas <- renderTable({
    req(resultado())
    df <- resultado()$areas
    data.frame(Classe = df$classe, Area_ha = round(df$area_ha, 2), Porcentagem = paste0(df$pct, "%"))
  }, striped = TRUE, bordered = TRUE)
}

shinyApp(ui, server)
