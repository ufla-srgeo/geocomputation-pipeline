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

# ==============================================================================
# MAPEAMENTO DE NOMES DAS CLASSES GEOMÓRFICAS
# ==============================================================================
nomes_classes <- c(
  "1"  = "Flat (Plano)",
  "2"  = "Peak (Pico)",
  "3"  = "Ridge (Crista)",
  "4"  = "Shoulder (Ombro)",
  "5"  = "Spur (Esporão)",
  "6"  = "Slope (Encosta)",
  "7"  = "Hollow (Concavidade)",
  "8"  = "Footslope (Sopé)",
  "9"  = "Valley (Vale)",
  "10" = "Pit (Depressão)"
)

# Paleta de cores das 10 classes (mesma ordem do rgeomorphon)
cores_classes <- c(
  "#FFFFC8", "#8B0000", "#FF4500", "#FF8C00", "#FFD700",
  "#9ACD32", "#228B22", "#006400", "#1E90FF", "#00008B"
)

# ==============================================================================
# UI
# ==============================================================================
ui <- fluidPage(

  # Estilo geral
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
      hr { border-color: #ecf0f1; }
      .status-box { border-left: 4px solid #27ae60; padding: 8px 12px;
                    background: #eafaf1; border-radius: 4px; font-size: 13px; }
    "))
  ),

  # Cabeçalho
  div(class = "titulo-app",
    h3("🌄 Pipeline Geomorfométrico Interativo"),
    p("Sensoriamento Remoto e Geoprocessamento open-source em R — UFLA Doutorado 2026")
  ),

  sidebarLayout(

    # ── Painel Lateral ────────────────────────────────────────────────────────
    sidebarPanel(width = 3,
      div(class = "painel-lateral",

        h4("📍 Município Alvo"),
        numericInput("cod_municipio",
                     "Geocódigo IBGE:",
                     value = 3108008,
                     min   = 1000000,
                     max   = 9999999),
        helpText("Ex: 3108008 = Bom Sucesso/MG"),

        hr(),
        h4("⚙️ Parâmetros Geomorphons"),

        sliderInput("search",
                    "Raio de busca (células):",
                    min = 3, max = 60, value = 7, step = 1),
        helpText("1 célula ≈ 90 m (res. SRTM)"),

        sliderInput("flat",
                    "Limiar de planeza (graus):",
                    min = 0.5, max = 5, value = 1, step = 0.5),

        selectInput("comparison_mode",
                    "Modo de comparação:",
                    choices = c("anglev1", "anglev2", "anglev2_distance"),
                    selected = "anglev1"),

        hr(),
        h4("📊 Visualização"),

        selectInput("tipo_grafico",
                    "Tipo de gráfico:",
                    choices = c("Barras por área (ha)"    = "barra",
                                "Barras por porcentagem"  = "pct",
                                "Mapa do relevo"          = "mapa")),

        hr(),
        actionButton("rodar", "▶  Executar Pipeline",
                     class = "btn-rodar")
      )
    ),

    # ── Painel Principal ──────────────────────────────────────────────────────
    mainPanel(width = 9,

      # Status do processamento
      uiOutput("status_ui"),

      # Estatísticas do MDE
      fluidRow(
        column(12,
          div(class = "painel-resultado",
            h4("📈 Estatísticas do Modelo Digital de Elevação"),
            uiOutput("estatisticas_mde")
          )
        )
      ),

      # Gráfico principal
      fluidRow(
        column(12,
          div(class = "painel-resultado",
            h4("🗺️ Resultado da Classificação"),
            plotOutput("grafico_principal", height = "420px")
          )
        )
      ),

      # Tabela de áreas
      fluidRow(
        column(12,
          div(class = "painel-resultado",
            h4("📋 Tabela de Distribuição por Classe"),
            tableOutput("tabela_areas")
          )
        )
      )
    )
  )
)

# ==============================================================================
# SERVER
# ==============================================================================
server <- function(input, output, session) {

  # ── Reatividade principal: executa ao clicar em "Rodar" ───────────────────
  resultado <- eventReactive(input$rodar, {

    withProgress(message = "Executando pipeline...", value = 0, {

      # --- 1. Dados vetoriais ------------------------------------------------
      incProgress(0.1, detail = "Baixando limites municipais (geobr)...")

      bs_sf <- tryCatch(
        read_municipality(code_muni = input$cod_municipio,
                          year = 2017, showProgress = FALSE),
        error = function(e) stop("Geocódigo inválido ou sem conexão com o IBGE.")
      )

      bs_v    <- vect(bs_sf)
      bs_wgs  <- project(bs_v, "EPSG:4326")

      # Centroide para buscar o tile SRTM correto
      centro  <- centroids(bs_wgs)
      lon_c   <- crds(centro)[1, 1]
      lat_c   <- crds(centro)[1, 2]

      # --- 2. MDE SRTM -------------------------------------------------------
      incProgress(0.3, detail = "Baixando dados de elevação SRTM...")

      alt <- tryCatch(
        elevation_3s(lon = lon_c, lat = lat_c, path = tempdir()),
        error = function(e) stop("Erro ao baixar dados SRTM. Verifique a conexão.")
      )

      bs_e <- crop(alt, bs_wgs, mask = TRUE)

      # Estatísticas do MDE
      vals      <- values(bs_e, na.rm = TRUE)
      stats_mde <- list(
        min    = round(min(vals),  1),
        max    = round(max(vals),  1),
        media  = round(mean(vals), 1),
        mediana= round(median(vals), 1),
        q1     = round(quantile(vals, 0.25), 1),
        q3     = round(quantile(vals, 0.75), 1),
        amp    = round(max(vals) - min(vals), 1)
      )

      # --- 3. Reprojeção e Geomorphons ---------------------------------------
      incProgress(0.5, detail = "Reprojetando para UTM e classificando relevo...")

      dem_real <- bs_e * 1
      dem_prj  <- project(dem_real, "EPSG:32723", method = "bilinear", res = 90)
      bs_prj   <- project(bs_wgs, "EPSG:32723")

      geo <- geomorphons(
        elevation       = dem_prj,
        search          = input$search,
        skip            = 1,
        dist            = 0,
        flat            = input$flat,
        comparison_mode = input$comparison_mode
      )

      # --- 4. Cálculo de áreas -----------------------------------------------
      incProgress(0.8, detail = "Calculando áreas por classe...")

      areas_df <- as.data.frame(
        expanse(geo, byValue = TRUE, unit = "ha")
      )
      colnames(areas_df) <- c("layer", "id_classe", "area_ha")

      areas_df$classe <- nomes_classes[as.character(areas_df$id_classe)]
      areas_df$pct    <- round(areas_df$area_ha / sum(areas_df$area_ha) * 100, 2)
      areas_df        <- areas_df[order(-areas_df$area_ha), ]

      incProgress(1.0, detail = "Concluído!")
    })

    list(
      areas_df  = areas_df,
      stats_mde = stats_mde,
      geo       = geo,
      bs_prj    = bs_prj,
      dem_prj   = dem_prj,
      bs_wgs    = bs_wgs,
      bs_e      = bs_e
    )
  })

  # ── Status ─────────────────────────────────────────────────────────────────
  output$status_ui <- renderUI({
    req(resultado())
    div(class = "status-box", style = "margin-bottom:14px;",
      "✅  Pipeline executado com sucesso! Geocódigo: ",
      strong(input$cod_municipio), " | Raio: ",
      strong(input$search), " células | Modo: ",
      strong(input$comparison_mode)
    )
  })

  # ── Estatísticas do MDE ────────────────────────────────────────────────────
  output$estatisticas_mde <- renderUI({
    req(resultado())
    s <- resultado()$stats_mde
    fluidRow(
      column(2, div(style="text-align:center;",
        h4(style="color:#2980b9; margin:0;", paste0(s$min, " m")),
        p(style="font-size:12px; color:#7f8c8d;", "Mínimo"))),
      column(2, div(style="text-align:center;",
        h4(style="color:#e74c3c; margin:0;", paste0(s$max, " m")),
        p(style="font-size:12px; color:#7f8c8d;", "Máximo"))),
      column(2, div(style="text-align:center;",
        h4(style="color:#8e44ad; margin:0;", paste0(s$media, " m")),
        p(style="font-size:12px; color:#7f8c8d;", "Média"))),
      column(2, div(style="text-align:center;",
        h4(style="color:#16a085; margin:0;", paste0(s$mediana, " m")),
        p(style="font-size:12px; color:#7f8c8d;", "Mediana"))),
      column(2, div(style="text-align:center;",
        h4(style="color:#d35400; margin:0;", paste0(s$amp, " m")),
        p(style="font-size:12px; color:#7f8c8d;", "Amplitude"))),
      column(2, div(style="text-align:center;",
        h4(style="color:#27ae60; margin:0;",
           paste0("Q1: ", s$q1, " | Q3: ", s$q3)),
        p(style="font-size:12px; color:#7f8c8d;", "Quartis")))
    )
  })

  # ── Gráfico principal ──────────────────────────────────────────────────────
  output$grafico_principal <- renderPlot({
    req(resultado())
    res  <- resultado()
    df   <- res$areas_df

    # Garantir ordem fatorizada para o gráfico
    df$classe <- factor(df$classe, levels = rev(df$classe))

    if (input$tipo_grafico == "barra") {

      ggplot(df, aes(x = classe, y = area_ha, fill = classe)) +
        geom_col(width = 0.7, show.legend = FALSE) +
        geom_text(aes(label = paste0(round(area_ha, 0), " ha")),
                  hjust = -0.1, size = 3.5) +
        coord_flip(clip = "off") +
        scale_fill_manual(values = setNames(cores_classes,
                                             levels(df$classe))) +
        labs(title = "Distribuição de Classes Geomórficas",
             subtitle = paste("Geocódigo:", input$cod_municipio,
                              "| Modo:", input$comparison_mode,
                              "| Search:", input$search),
             x = NULL, y = "Área (Hectares)") +
        theme_minimal(base_size = 13) +
        theme(plot.title = element_text(face = "bold"))

    } else if (input$tipo_grafico == "pct") {

      ggplot(df, aes(x = classe, y = pct, fill = classe)) +
        geom_col(width = 0.7, show.legend = FALSE) +
        geom_text(aes(label = paste0(pct, "%")),
                  hjust = -0.1, size = 3.5) +
        coord_flip(clip = "off") +
        scale_fill_manual(values = setNames(cores_classes,
                                             levels(df$classe))) +
        labs(title = "Porcentagem por Classe Geomórfica",
             subtitle = paste("Geocódigo:", input$cod_municipio),
             x = NULL, y = "Porcentagem (%)") +
        theme_minimal(base_size = 13) +
        theme(plot.title = element_text(face = "bold"))

    } else {

      # Mapa do raster geomórfico com vetor sobreposto
      par(mar = c(2, 2, 3, 5))
      plot(res$geo, col = cores_classes,
           main = paste("Classes Geomórficas —", input$cod_municipio),
           legend = TRUE)
      plot(res$bs_prj, add = TRUE, border = "black", lwd = 1.5)
    }
  })

  # ── Tabela de áreas ────────────────────────────────────────────────────────
  output$tabela_areas <- renderTable({
    req(resultado())
    df <- resultado()$areas_df
    df_tabela <- data.frame(
      "Classe"       = df$classe,
      "Área (ha)"    = round(df$area_ha, 2),
      "Porcentagem"  = paste0(df$pct, "%"),
      check.names    = FALSE
    )
    df_tabela
  }, striped = TRUE, hover = TRUE, bordered = TRUE, align = "lrr")

}

# ==============================================================================
# INICIALIZAR APP
# ==============================================================================
shinyApp(ui = ui, server = server)
