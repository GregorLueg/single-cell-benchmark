# Figures for the README and docs. Reads docs/figures/results_long.csv
# (uv run scripts/tables.py --long results > docs/figures/results_long.csv).
# Usage: Rscript scripts/plots.R

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(patchwork)
  library(ggrepel)
})

fig_dir <- "docs/figures"
dt_all <- fread(file.path(fig_dir, "results_long.csv"))
dt <- dt_all[startsWith(size, "parse")]

# palette: validated categorical slots 1-4, one per framework family
family_cols <- c(
  bixverse = "#2a78d6",
  Scanpy = "#eb6834",
  scrapper = "#1baf7a",
  Seurat = "#eda100"
)
surface <- "#fcfcfb"
ink <- "#0b0b0b"
ink_2 <- "#52514e"
grid_col <- "#e4e3df"

column_order <- c(
  "bixverse mtx", "bixverse h5ad", "bixverse GPU*", "bixverse MLX*",
  "Scanpy mtx", "Scanpy h5ad", "Scanpy dask",
  "scrapper mtx", "scrapper h5ad", "scrapper HDF5",
  "Seurat std mtx", "Seurat std h5ad", "Seurat BPCells"
)
step_order <- c(
  "load", "qc", "normalise", "hvg", "pca", "harmony", "knn_snn", "cluster",
  "cluster_fast", "umap", "dge", "tsne_default", "tsne_fft", "tsne_quick"
)
size_labels <- c(
  parse_100k = "100k (69,412 cells)",
  parse_500k = "500k (346,259 cells)",
  parse_full = "full (684,932 cells)"
)

dt[, family := sub(" .*", "", column)]
dt[, column := factor(column, levels = column_order)]
dt[, step := factor(step, levels = step_order)]
dt[, design := fcase(
  column %in% c("bixverse GPU*", "bixverse MLX*"), "out-of-core, native GPU (uncapped)",
  family == "bixverse" | column %in% c("Scanpy dask", "Seurat BPCells", "scrapper HDF5"), "out-of-core",
  default = "in-memory"
)]

theme_bench <- function(base_size = 10) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background = element_rect(fill = surface, colour = NA),
      panel.background = element_rect(fill = surface, colour = NA),
      panel.grid.major = element_line(colour = grid_col, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      text = element_text(colour = ink),
      axis.text = element_text(colour = ink_2),
      plot.title = element_text(face = "bold", size = base_size + 1),
      plot.subtitle = element_text(colour = ink_2),
      plot.caption = element_text(colour = ink_2, hjust = 0),
      legend.position = "bottom",
      strip.text = element_text(face = "bold", hjust = 0)
    )
}

#### figure 1: scaling ----------------------------------------------------------

runs <- dt[, .(
  cells = cells[1],
  family = family[1],
  design = design[1],
  status = if (any(status != "ok")) status[status != "ok"][1] else "ok",
  no_tsne = sum(seconds[!grepl("^tsne|^cluster_fast", step)], na.rm = TRUE),
  total = sum(seconds[step != "cluster_fast"], na.rm = TRUE),
  peak_gb = peak_gb[1]
), by = .(column, size)]
runs[status != "ok", c("no_tsne", "total") := NA_real_]

ok <- runs[status == "ok"]
failed <- runs[status != "ok"]
cell_breaks <- c(69412, 346259, 684932)
cell_labels <- c("69k", "346k", "685k")

scaling_panel <- function(y, title, label_lines) {
  d <- ok[, .(column, family, design, cells, y = get(y))]
  y_fail <- max(d$y) * 2
  # one cross per failed run, stacked upwards within the "died" band
  f <- failed[order(cells, column)]
  f[, y_cross := y_fail * 1.16^(seq_len(.N) - 1), by = cells]
  last <- d[, .SD[which.max(cells)], by = column]
  band_low <- y_fail / 1.35
  y_breaks <- 10^(1:5)
  p <- ggplot(d, aes(cells, y, group = column, colour = family, linetype = design)) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = band_low, ymax = Inf, fill = "#ecebe6") +
    geom_hline(yintercept = band_low, colour = ink_2, linewidth = 0.3, linetype = "22") +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2, stroke = 0) +
    geom_point(
      data = f,
      aes(cells, y_cross, colour = family),
      inherit.aes = FALSE,
      shape = 4, size = 2.6, stroke = 1
    ) +
    annotate(
      "text", x = max(cell_breaks) * 1.12, y = y_fail, label = "died (OOM)",
      hjust = 0, colour = ink_2, size = 3
    ) +
    scale_x_log10(breaks = cell_breaks, labels = cell_labels) +
    scale_y_log10(
      breaks = y_breaks[y_breaks < band_low],
      labels = scales::label_number(suffix = " s", big.mark = ",")
    ) +
    scale_colour_manual(values = family_cols, name = NULL) +
    scale_linetype_manual(
      values = c("out-of-core" = "solid", "in-memory" = "22", "out-of-core, native GPU (uncapped)" = "13"),
      name = NULL
    ) +
    coord_cartesian(clip = "off") +
    theme(panel.grid.major.y = element_line(colour = grid_col, linewidth = 0.3)) +
    labs(title = title, x = "cells after QC", y = NULL) +
    theme_bench()
  if (label_lines) {
    p <- p + geom_text_repel(
      data = last,
      aes(label = column),
      colour = ink_2, size = 2.6, direction = "y", hjust = 0,
      nudge_x = 0.12, segment.colour = grid_col, min.segment.length = 0,
      show.legend = FALSE
    ) +
      scale_x_log10(breaks = cell_breaks, labels = cell_labels, expand = expansion(mult = c(0.05, 0.45)))
  }
  p
}

p_no_tsne <- scaling_panel("no_tsne", "Without tSNE", TRUE)
p_total <- scaling_panel("total", "Total, incl. tSNE", FALSE)

p_mem <- ggplot(runs, aes(cells, peak_gb, group = column, colour = family, linetype = design)) +
  geom_hline(yintercept = 24, colour = ink_2, linetype = "22", linewidth = 0.4) +
  annotate("text", x = min(cell_breaks), y = 24, label = "24 GB cap", vjust = -0.6, hjust = 0, colour = ink_2, size = 3) +
  geom_line(data = ok, linewidth = 0.7) +
  geom_point(data = ok, size = 2, stroke = 0) +
  geom_point(data = failed, shape = 4, size = 2.6, stroke = 1) +
  scale_x_log10(breaks = cell_breaks, labels = cell_labels) +
  scale_y_continuous(labels = scales::label_number(suffix = " GB"), limits = c(0, 26)) +
  scale_colour_manual(values = family_cols, name = NULL) +
  scale_linetype_manual(
    values = c("out-of-core" = "solid", "in-memory" = "22", "out-of-core, native GPU (uncapped)" = "13"),
    name = NULL
  ) +
  labs(title = "Peak memory", x = "cells after QC", y = NULL) +
  theme_bench()

fig1 <- (p_no_tsne | p_total | p_mem) +
  plot_layout(guides = "collect", widths = c(1.35, 1, 1)) +
  plot_annotation(
    title = "Parse 1M PBMC under a 24 GB, 8 core cap",
    subtitle = "One repeat per run. Crosses mark the size where a run died (OOM), plotted at the cap on the memory panel.",
    caption = "bixverse GPU (wgpu) and MLX run natively on Metal without a memory cap; their peak is process RSS. Scanpy dask has no DGE step.",
    theme = theme_bench()
  ) &
  theme(legend.position = "bottom")

ggsave(file.path(fig_dir, "scaling.png"), fig1, width = 13, height = 5, dpi = 200, bg = surface)
ggsave(file.path(fig_dir, "scaling.pdf"), fig1, width = 13, height = 5, bg = surface)

#### figure 2: per-step heatmap, each step scaled across frameworks -----------

# heatmap0 without its near-black first slot, which marks missing tiles instead
step_ramp <- c("#005F73", "#0A9396", "#94D2BD", "#E9D8A6", "#EE9B00", "#CA6702", "#AE2012", "#9B2226")
missing_fill <- "#001219"
no_step <- list(
  bixverse = "normalise",
  Scanpy = c("cluster_fast", "tsne_quick"),
  Seurat = c("cluster_fast", "tsne_quick"),
  scrapper = c("tsne_default", "tsne_fft")
)
total_step <- "total (no tSNE)"

step_heatmap <- function(labels, title, file, height) {
  d <- dt_all[size %in% names(labels)]
  d[, family := sub(" .*", "", column)]
  # a run that died in a tSNE step still has a total without tSNE
  tot <- d[, {
    died <- any(status != "ok" & !grepl("^tsne", step))
    .(
      step = total_step,
      seconds = if (died) NA_real_ else sum(seconds[!grepl("^tsne|^cluster_fast", step)], na.rm = TRUE),
      status = if (died) "failed" else "ok"
    )
  }, by = .(column, size, family)]
  d <- rbind(d[, .(column, size, family, step, seconds, status)], tot)
  grid <- unique(d[, .(column, size, family)])[, .(step = c(step_order, total_step)), by = .(column, size, family)]
  d <- merge(grid, d, by = c("column", "size", "family", "step"), all.x = TRUE)
  d[, lab := fcase(
    mapply(function(f, s) s %in% no_step[[f]], family, step), "n/a",
    !is.na(status) & status != "ok", sub(" ", "\n", status),
    is.na(seconds), "-",
    seconds < 10, sprintf("%.1f", seconds),
    default = format(round(seconds), big.mark = ",", trim = TRUE)
  )]
  d[!is.na(status) & status != "ok", seconds := NA_real_]
  # 0 = fastest framework on that step, 1 = slowest, linear in sqrt(seconds)
  d[, scaled := {
    seconds <- sqrt(seconds)
    r <- suppressWarnings(range(seconds, na.rm = TRUE))
    if (all(is.na(seconds))) NA_real_ else if (r[1] == r[2]) 0 else (seconds - r[1]) / (r[2] - r[1])
  }, by = .(size, step)]
  d <- d[, if (any(!is.na(seconds))) .SD, by = .(size, step)]
  d[, size_label := factor(labels[size], levels = labels)]
  d[, column := factor(column, levels = column_order)]
  d[, step := factor(step, levels = rev(c(step_order, total_step)))]
  d[, light := !is.na(scaled) & scaled > 0.2 & scaled < 0.6]

  p <- ggplot(d, aes(column, step)) +
    geom_tile(aes(fill = scaled), colour = surface, linewidth = 0.8) +
    geom_text(aes(label = lab, colour = light), size = 2.4, lineheight = 0.85, show.legend = FALSE) +
    scale_fill_gradientn(
      colours = step_ramp, limits = c(0, 1), na.value = missing_fill,
      breaks = c(0, 1), labels = c("fastest", "slowest"), name = "per step"
    ) +
    scale_colour_manual(values = c(`FALSE` = "#ffffff", `TRUE` = ink)) +
    facet_wrap(~size_label, ncol = 1, scales = "free_x") +
    labs(
      title = title,
      subtitle = "Seconds per step. Colour is scaled per step and size: fastest framework 0, slowest 1, on square-root seconds.",
      caption = paste(
        "Black: n/a (step not in that framework), OOM or TIMEOUT where the run died, - not reached.",
        "Each step is scaled over the runs that finished it: at 1M the bixverse CPU tSNE is red because the others timed out.",
        "Scanpy dask has no DGE step. bixverse GPU and MLX run natively without a memory cap.",
        "bixverse CPU tSNE builds its kNN with IVF from 500k (kmknn at 100k). (qd) steps are not in the total.",
        sep = "\n"
      ),
      x = NULL, y = NULL
    ) +
    theme_bench() +
    theme(
      panel.grid.major = element_blank(),
      axis.text.x = element_text(angle = 35, hjust = 1),
      legend.key.width = unit(1.6, "cm")
    )

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = 11, height = height, dpi = 200, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = 11, height = height, bg = surface)
}

step_heatmap(
  c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
  "Wall time per step: Splat simulation", "steps_heatmap_splat", 16
)
step_heatmap(size_labels, "Wall time per step: Parse 1M PBMC", "steps_heatmap_pbmc", 16)

#### figure 3: speed-up per step against a Scanpy reference ------------------

# normalisation is deferred in Dask and scrapper (normalizeCounts(delayed = TRUE)):
# the cost lands in later steps, so a fold change against or of it is meaningless
lazy_cols <- c("Scanpy dask", "scrapper h5ad")

speedup_plot <- function(size_key, ref_col, title, subtitle, caption, file, height) {
  d <- dt[size == size_key & status == "ok"]
  survivors <- runs[size == size_key & status == "ok" & column != ref_col, as.character(column)]
  tot <- runs[size == size_key & status == "ok", .(column, step = "total (no tSNE)", seconds = no_tsne)]
  fc <- rbind(d[, .(column, step = as.character(step), seconds)], tot)
  ref <- fc[column == ref_col, .(step, ref_s = seconds)]
  fc <- merge(fc[column %in% survivors], ref, by = "step")
  fc[, fold := ref_s / seconds]
  fc[, lazy := step == "normalise" & (column %in% lazy_cols | ref_col %in% lazy_cols)]
  fc[lazy == TRUE, fold := NA_real_]
  fc[, step := factor(step, levels = c(step_order, "total (no tSNE)"))]
  fc[, column := factor(column, levels = rev(column_order))]
  fc[, lab := fcase(
    lazy, "lazy",
    fold >= 10, sprintf("%.0fx", fold),
    fold < 0.1, sprintf("%.2fx", fold),
    default = sprintf("%.1fx", fold)
  )]
  lim <- log2(32)

  p <- ggplot(fc, aes(step, column)) +
    geom_tile(aes(fill = pmax(pmin(log2(fold), lim), -lim)), colour = surface, linewidth = 0.8) +
    geom_text(
      aes(label = lab, colour = is.na(fold) | log2(fold) < -2 | log2(fold) > 2.7),
      size = 2.6, show.legend = FALSE
    ) +
    scale_colour_manual(values = c(`FALSE` = ink, `TRUE` = "#ffffff")) +
    # the heatmap ramp reversed, beige pinned to "same"
    scale_fill_gradientn(
      colours = rev(step_ramp), values = c(0, 0.125, 0.25, 0.375, 0.5, 2 / 3, 5 / 6, 1),
      na.value = missing_fill,
      limits = c(-lim, lim),
      breaks = log2(c(1 / 16, 1 / 4, 1, 4, 16)),
      labels = c("16x slower", "4x slower", "same", "4x faster", "16x faster"),
      name = NULL
    ) +
    labs(title = title, subtitle = subtitle, caption = caption, x = NULL, y = NULL) +
    theme_bench() +
    theme(
      panel.grid.major = element_blank(),
      axis.text.x = element_text(angle = 35, hjust = 1),
      legend.key.width = unit(1.8, "cm")
    )

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = 9.5, height = height, dpi = 200, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = 9.5, height = height, bg = surface)
}

speedup_plot(
  "parse_500k", "Scanpy h5ad",
  title = "Speed-up per step against in-memory Scanpy (h5ad), 500k",
  subtitle = "The largest size in-memory Scanpy survives. Only runs that completed at 500k.",
  caption = paste(
    "bixverse normalises during load. Scanpy dask has no DGE step. bixverse CPU tSNE builds its kNN with IVF.",
    "tsne_quick (qdtsne) and cluster_fast (Leiden on k-means centroids) are not shown and not in the total.",
    sep = "\n"
  ),
  file = "speedup_vs_scanpy_500k",
  height = 4
)

speedup_plot(
  "parse_full", "Scanpy dask",
  title = "Speed-up per step against Scanpy with Dask, full data set",
  subtitle = "In-memory Scanpy dies at load here; Dask is the Scanpy path that finishes. Only runs that completed.",
  caption = paste(
    "bixverse normalises during load; Dask defers normalisation, so the normalise column carries no fold change.",
    "Dask has no DGE step (Wilcoxon fails on Dask arrays), so its total lacks one; in-memory Scanpy's takes 602 s at 500k.",
    "bixverse CPU tSNE builds its kNN with IVF.",
    sep = "\n"
  ),
  file = "speedup_vs_scanpy_dask_full",
  height = 3.2
)

#### figure 4: cold vs warm load ------------------------------------------------

# warm_long.csv: uv run scripts/tables.py --warm results > docs/figures/warm_long.csv
wl <- fread(file.path(fig_dir, "warm_long.csv"))
wl[, size_label := factor(size_labels[size], levels = size_labels)]
wl[, start := factor(start, levels = c("cold", "warm"))]
wl[, family := sub(" .*", "", framework)]

fig4 <- ggplot(wl, aes(size_label, seconds, fill = start)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(
    aes(label = sprintf(ifelse(seconds < 10, "%.1f s", "%.0f s"), seconds)),
    position = position_dodge(width = 0.8), vjust = -0.4, size = 2.8, colour = ink
  ) +
  facet_wrap(~framework) +
  scale_fill_manual(values = c(cold = step_ramp[3], warm = step_ramp[1]), name = NULL) +
  scale_y_continuous(
    labels = scales::label_number(suffix = " s"),
    expand = expansion(mult = c(0, 0.1))
  ) +
  labs(
    title = "Load: cold conversion against a warm reconnect",
    subtitle = "Warm reopens what the cold run wrote to disk. One repeat each, run straight after the cold run.",
    caption = "bixverse cold load from mtx. BPCells warm reopens the pre-filtered, pre-QC matrix.",
    x = NULL, y = NULL
  ) +
  theme_bench() +
  theme(panel.grid.major.x = element_blank())

ggsave(file.path(fig_dir, "warm_start.png"), fig4, width = 8, height = 3.6, dpi = 200, bg = surface)
ggsave(file.path(fig_dir, "warm_start.pdf"), fig4, width = 8, height = 3.6, bg = surface)
