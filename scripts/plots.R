# Figures for the README and docs. Reads docs/figures/results_long.csv
# (uv run scripts/tables.py --long results > docs/figures/results_long.csv).
# Usage: Rscript scripts/plots.R

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(patchwork)
})

fig_dir <- "docs/figures"
dt_all <- fread(file.path(fig_dir, "results_long.csv"))
dt <- dt_all[startsWith(size, "parse")]

# one per framework family, from the lto "hat" palette
family_cols <- c(
  bixverse = "#0F8096",
  Scanpy = "#E8351E",
  scrapper = "#17A769",
  Seurat = "#852F88",
  CyteArc = "#D98E04"
)
surface <- "#fcfcfb"
ink <- "#0b0b0b"
ink_2 <- "#52514e"
grid_col <- "#e4e3df"

column_order <- c(
  "bixverse mtx", "bixverse h5ad", "bixverse GPU*", "bixverse MLX*",
  "Scanpy mtx", "Scanpy h5ad", "Scanpy dask",
  "scrapper mtx", "scrapper h5ad", "scrapper HDF5",
  "Seurat std mtx", "Seurat std h5ad", "Seurat BPCells",
  "CyteArc mtx", "CyteArc h5ad"
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

#### figure 1: time and memory per size ---------------------------------------

run_summary <- function(d) {
  d[, .(
    family = sub(" .*", "", column[1]),
    # a run that died in a tSNE step still has a time without tSNE
    died = {
      bad <- status != "ok" & !grepl("^tsne", step)
      if (any(bad)) paste(status[bad][1], "at", step[bad][1]) else NA_character_
    },
    no_tsne = sum(seconds[!grepl("^tsne|^cluster_fast", step)], na.rm = TRUE),
    peak_gb = peak_gb[1]
  ), by = .(column, size)]
}

runs <- run_summary(dt)
runs[, status := fifelse(is.na(died), "ok", "failed")]
runs[status != "ok", no_tsne := NA_real_]

scaling_bars <- function(labels, title, file) {
  r <- run_summary(dt_all[size %in% names(labels)])
  r[!is.na(died), no_tsne := NA_real_]
  r[, size_label := factor(labels[size], levels = labels)]
  r[, column := factor(column, levels = rev(column_order))]
  r[, native := column %in% c("bixverse GPU*", "bixverse MLX*")]
  x_min <- 5

  p_time <- ggplot(r, aes(y = column)) +
    geom_col(aes(x = no_tsne, fill = family, alpha = native), width = 0.75, na.rm = TRUE) +
    geom_text(
      aes(x = no_tsne, label = format(round(no_tsne), big.mark = ",", trim = TRUE)),
      hjust = -0.15, size = 3.6, colour = ink, na.rm = TRUE
    ) +
    geom_text(
      data = r[!is.na(died)], aes(x = x_min, label = died),
      hjust = 0, size = 3.6, colour = ink_2, nudge_x = 0.02
    ) +
    scale_x_log10(
      limits = c(x_min, NA), oob = scales::oob_keep, breaks = c(10, 100, 1000), labels = c("10 s", "100 s", "1,000 s"),
      expand = expansion(mult = c(0, 0.3))
    ) +
    facet_wrap(~size_label, nrow = 1) +
    labs(title = "Without tSNE", x = NULL, y = NULL)

  p_mem <- ggplot(r, aes(y = column)) +
    geom_col(aes(x = peak_gb, fill = family, alpha = native), width = 0.75) +
    geom_vline(xintercept = 24, linetype = "dotted", colour = ink_2) +
    geom_text(
      aes(
        x = peak_gb, label = paste0(sprintf("%.1f", peak_gb), fifelse(is.na(died), "", ", died")),
        hjust = fifelse(peak_gb > 18, 1.1, -0.15), colour = peak_gb > 18
      ),
      size = 3.6, show.legend = FALSE
    ) +
    scale_colour_manual(values = c(`FALSE` = ink, `TRUE` = "#ffffff")) +
    scale_x_continuous(breaks = c(0, 8, 16, 24), labels = c("0", "8", "16", "24"),
                       expand = expansion(mult = c(0, 0.08))) +
    facet_wrap(~size_label, nrow = 1) +
    labs(title = "Peak memory (GB); dotted: the 24 GB cap", x = NULL, y = NULL)

  p <- (p_time / p_mem) + plot_layout(guides = "collect") +
    plot_annotation(
      title = title,
      subtitle = "Under a 24 GB, 8 core cap. One repeat per run; a run that died shows where.",
      caption = paste(
        "Faded: bixverse GPU (wgpu) and MLX, native on Metal without a memory cap; their peak is the macOS memory footprint.",
        "Scanpy dask has no DGE step. A run that timed out in tSNE keeps its time without tSNE.",
        sep = "\n"
      ),
      theme = theme_bench(14)
    ) &
    scale_fill_manual(values = family_cols, name = NULL) &
    scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = 0.55), guide = "none") &
    theme_bench(14) &
    theme(panel.grid.major.y = element_blank(), legend.position = "bottom")

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = 14, height = 11, dpi = 300, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = 14, height = 11, bg = surface)
}

scaling_bars(
  c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
  "Splat simulation: time and memory", "scaling_splat"
)
scaling_bars(size_labels, "Parse 1M PBMC: time and memory", "scaling_pbmc")

#### figure 2: per-step heatmap, each step scaled across frameworks -----------

# heatmap0 without its near-black first slot, which marks missing tiles instead
step_ramp <- c("#005F73", "#0A9396", "#94D2BD", "#E9D8A6", "#EE9B00", "#CA6702", "#AE2012", "#9B2226")
missing_fill <- "#001219"
no_step <- list(
  bixverse = "normalise",
  Scanpy = c("cluster_fast", "tsne_quick"),
  Seurat = c("cluster_fast", "tsne_quick"),
  scrapper = c("tsne_default", "tsne_fft"),
  CyteArc = c("cluster_fast", "tsne_default", "tsne_fft", "tsne_quick")
)
total_step <- "total (no tSNE)"

step_heatmap <- function(labels, title, file, height, width = 11, base_size = 10, text_size = 2.4) {
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
    geom_text(aes(label = lab, colour = light), size = text_size, lineheight = 0.85, show.legend = FALSE) +
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
    theme_bench(base_size) +
    theme(
      panel.grid.major = element_blank(),
      axis.text.x = element_text(angle = 35, hjust = 1),
      legend.key.width = unit(1.6, "cm")
    )
  # the size is in the title already
  if (length(labels) == 1) p <- p + theme(strip.text = element_blank())

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = width, height = height, dpi = 300, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = width, height = height, bg = surface)
}

step_heatmap(
  c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
  "Wall time per step: Splat simulation", "steps_heatmap_splat", 16
)
step_heatmap(size_labels, "Wall time per step: Parse 1M PBMC", "steps_heatmap_pbmc", 16)

# one figure per size, larger type
for (lst in list(
  list(c(splat_100k = "100k (96,342 cells)", splat_500k = "500k (482,409 cells)", splat_1m = "1M (964,763 cells)"),
       "Splat simulation", "splat"),
  list(size_labels, "Parse 1M PBMC", "pbmc")
)) {
  for (k in names(lst[[1]])) {
    step_heatmap(
      lst[[1]][k], paste0("Wall time per step: ", lst[[2]], ", ", lst[[1]][k]),
      paste0("steps_heatmap_", lst[[3]], "_", sub(".*_", "", k)),
      height = 9.5, width = 13, base_size = 14, text_size = 3.6
    )
  }
}

#### figure 3: speed-up per step against a Scanpy reference ------------------

# normalisation is deferred in Dask, scrapper (normalizeCounts(delayed = TRUE)) and CyteArc:
# the cost lands in later steps, so a fold change against or of it is meaningless
lazy_cols <- c("Scanpy dask", "scrapper h5ad", "scrapper HDF5", "CyteArc mtx", "CyteArc h5ad")

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
      size = 3.6, show.legend = FALSE
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
    theme_bench(14) +
    theme(
      panel.grid.major = element_blank(),
      axis.text.x = element_text(angle = 35, hjust = 1),
      legend.key.width = unit(2.2, "cm")
    )

  ggsave(file.path(fig_dir, paste0(file, ".png")), p, width = 13, height = height, dpi = 300, bg = surface)
  ggsave(file.path(fig_dir, paste0(file, ".pdf")), p, width = 13, height = height, bg = surface)
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
  height = 5.6
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
  height = 4.6
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

ggsave(file.path(fig_dir, "warm_start.png"), fig4, width = 8, height = 3.6, dpi = 300, bg = surface)
ggsave(file.path(fig_dir, "warm_start.pdf"), fig4, width = 8, height = 3.6, bg = surface)
