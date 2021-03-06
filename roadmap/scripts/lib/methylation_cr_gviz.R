# check version of Gviz
if(compareVersion(sessionInfo()$otherPkgs$Gviz$Version, "9.9.0") < 0) {
	stop("please use a modified Gviz from 'https://github.com/jokergoo/Gviz'.")
}

if(!exists(".boxes")) {
	.boxes = Gviz:::.boxes
}
if(!exists(".arrowBar")) {
	.arrowBar = Gviz:::.arrowBar
}
if(!exists(".fontGp")) {
	.fontGp = Gviz:::.fontGp
}

# == title
# Customized Gviz plot for a gene model
#
# == param
# -cr correlated regions generated by `filter_correlated_regions`
# -gi gene id
# -expr the expression matrix which is same as in `correlated_regions`
# -txdb a ``GenomicFeatures::GRanges`` object.
# -gene_start start position of gene
# -gene_end end position of the gene
# -species species
# -gf_list a list of `GenomicRanges::GRanges` objects which contains additional annotations
# -hm_list a list of `GenomicRanges::GRanges`
# -symbol symbol of the gene
#
# == details
# Several information on the correlated regions in an extended gene model are visualized by Gviz package:
#
# - gene models. Multiple transcripts will also be plotted.
# - correlation for every CpG window
# - heatmap for methylation
# - significant correlated regions
# - CpG density
# - annotation to other genomic features if provided
# - annotation to other ChIP-Seq peak data if provided
#
# == value
# No value is returned.
#
# == author
# Zuguang Gu <z.gu@dkfz.de>
#
cr_gviz = function(cr, gi, expr, txdb, gene_start = NULL, gene_end = NULL, 
	species = "hg19", gf_list = NULL, hm_list = NULL, symbol = NULL) {

	sample_id = attr(cr, "sample_id")
	extend = attr(cr, "extend")
	window_size = attr(cr, "window_size")
	window_step = attr(cr, "window_step")
	max_width = attr(cr, "max_width")
	cor_method = attr(cr, "cor_method")
	factor = attr(cr, "factor")
	cov_filter = attr(cr, "cov_filter")
	raw_meth = attr(cr, "raw_meth")
	cov_cutoff = attr(cr, "cov_cutoff")
	min_dp = attr(cr, "min_dp")

	if(is.null(raw_meth)) raw_meth = FALSE
	if(is.null(cov_cutoff)) cov_cutoff = 0
	if(is.null(min_dp)) min_dp = 5
	if(!raw_meth) cov_cutoff = 0
	
	if(!gi %in% cr$gene_id) {
		stop(paste0("cannot find ", gi, "in cr.\n"))
	}

	chr = as.vector(seqnames(cr[cr$gene_id == gi]))[1]
	cr = cr[cr$gene_id == gi]

	if(is.null(methylation_hooks$obj)) methylation_hooks$set(chr)
	if(attr(methylation_hooks$obj, "chr") != chr) methylation_hooks$set(chr)
	
	e = expr[gi, sample_id]

	if(is.null(gene_start) || is.null(gene_end)) {
		gene = genes(txdb)
		gene_start = start(gene[gi])
		gene_end = end(gene[gi])
	}

	gene_start = gene_start - extend
	gene_end = gene_end + extend

	site = methylation_hooks$site()

	gm_site_index = extract_sites(gene_start, gene_end, site, TRUE, 0)
	gm_site = site[gm_site_index]
	gm_meth = methylation_hooks$meth(row_index = gm_site_index, col_index = sample_id)
	gm_cov = methylation_hooks$coverage(row_index = gm_site_index, col_index = sample_id)

	if(!is.null(cov_filter)) {
		l = apply(gm_cov, 1, cov_filter)
		gm_site = gm_site[l]
		gm_meth = gm_meth[l, , drop = FALSE]
		gm_cov = gm_cov[l, , drop = FALSE]
	}

	qqcat("rescan on @{gi} to calculate corr in @{window_size} bp cpg window...\n")
	
	gr = correlated_regions_per_gene(gm_site, gm_meth, gm_cov, e, cov_cutoff = cov_cutoff, chr = chr,
			factor = factor, cor_method = cor_method, window_size = window_size, window_step = window_step, min_dp = min_dp,
			max_width = max_width)
	qqcat("add transcripts to gviz tracks...\n")
	options(Gviz.ucscUrl="http://genome-euro.ucsc.edu/cgi-bin/")
	trackList = list()
	trackList = pushTrackList(trackList, GenomeAxisTrack())
	trackList = pushTrackList(trackList, IdeogramTrack(genome = species, chromosome = chr))
	grtrack = GeneRegionTrack(txdb, chromosome = chr, start = gene_start, end = gene_end, 
		name="Gene\nmodel", showId = TRUE, rotate.title = TRUE, col = NA, showTitle = FALSE)
	
	# tx_list = transcriptsBy(txdb, by = "gene")
	# tx_list = tx_list[[gi]]$tx_name
	# sg = symbol(grtrack)
	# sg[sg %in% tx_list] = paste0("[", sg[sg %in% tx_list], "]")
	# symbol(grtrack) = sg
	# browser()
	# mtch = as.matrix(findOverlaps(GRanges(seqnames = chr, ranges = IRanges(gene_start, gene_end)), grtrack@range))
	# fill = ifelse(grtrack@range[unique(mtch[,2])]$gene == gi, "pink", "#FFA500")
	# grtrack@dp@pars$fill = fill
			
	.boxes_wrap = function(GdObject, offsets) {
		df = .boxes(GdObject, offsets)
		l = df$gene == gi
		# df$fill[l] = "pink"
		df$fill[!l] = paste0(df$fill[!l], "40")
		df
	}
	assignInNamespace(".boxes", .boxes_wrap, "Gviz")
	

	tx_gene_mapping = structure(grtrack@range$gene, names = grtrack@range$transcript)

	.arrowBar_wrap = function(xx1, xx2, strand, coords, y=20, W=3, D=10, H, col, lwd, lty, alpha, barOnly=FALSE,
        diff=.pxResolution(coord="y"), min.height=3) {
		env = parent.frame()
		if("bar" %in% ls(envir = env)) {
			bar = get("bar", envir = env)
			arrow_col = ifelse(tx_gene_mapping[rownames(bar)] == gi, "darkgrey", "#E0E0E0")
		}
		.arrowBar(xx1 = xx1, xx2 = xx2, strand = strand, coords = coords, y=y, W=W, D=D, H, col = arrow_col, lwd = lwd, lty = lty, alpha = alpha, barOnly=barOnly,
        	diff=diff, min.height=min.height)
	}
	assignInNamespace(".arrowBar", .arrowBar_wrap, "Gviz")
	
	.fontGp_wrap = function(GdObject, subtype = NULL, ...) {
		gp = .fontGp(GdObject, subtype, ...)
		if(!is.null(subtype)) {
			if(subtype == "group") {
				env = parent.frame()
				if("bartext" %in% ls(envir = env)) {
					bartext = get("bartext", envir = env)
					tx_name = bartext$txt
					l = tx_gene_mapping[tx_name] == gi
					gp$col = ifelse(l, "#808080", "#E0E0E0")
				}
			}
		}
		return(gp)
	}
	assignInNamespace(".fontGp", .fontGp_wrap, "Gviz")
	

	trackList = pushTrackList(trackList, grtrack)

	## correlation track
	qqcat("add correlation line to gviz tracks...\n")
	corr_mat = matrix(0, nrow = 2, ncol = length(gr$corr))
	corr_mat[1, gr$corr > 0] = gr$corr[gr$corr > 0]
	corr_mat[2, gr$corr < 0] = gr$corr[gr$corr < 0]
	trackList = pushTrackList(trackList, DataTrack(name = qq("Correlation\nCpG window = @{window_size}"),
								range = gr,
								genome = species,
								data = corr_mat,
								type = c("hist"),
								groups = c("pos", "neg"),
								fill.histogram = c("red", "green"),
								col.histogram = NA,
								ylim = c(-1, 1), legend = FALSE,
								panelFun = local({window_size = window_size; function() grid.text(qq("Correlation, CpG window = @{window_size}bp"), 0, unit(1, "npc") - unit(2, "mm"), just = c("left", "top"))}),
								size = 1.5))

	qqcat("add cr to gviz tracks...\n")
	pos_cr = cr[cr$corr > 0]
	if(length(pos_cr))
		trackList = pushTrackList(trackList, constructAnnotationTrack(reduce(pos_cr), chr, name = "sig_pos_cr", fill = "red", col = NA, 
			rotate.title = TRUE, start = gene_start, end = gene_end, size = 0.5,
			panelFun = function() {grid.text("pos_cr", 0, unit(0.5, "npc"), just = c("left", "center"))},))
	neg_cr = cr[cr$corr < 0]
	if(length(neg_cr))
		trackList = pushTrackList(trackList, constructAnnotationTrack(reduce(neg_cr), chr, name = "sig_neg_cr", fill = "darkgreen", col = NA, 
			rotate.title = TRUE, start = gene_start, end = gene_end, size = 0.5,
			panelFun = function() {grid.text("neg_cr", 0, unit(0.5, "npc"), just = c("left", "center"))},))

	qqcat("add methylation to gviz tracks...\n")
	meth_mat = as.matrix(mcols(gr)[, paste0("mean_meth_", sample_id)])
	colnames(meth_mat) = NULL
	if(is.null(factor)) {
		trackList = pushTrackList(trackList, DataTrack(name = "meth",
										start = start(gr),
										end = end(gr),
										chromosome = seqnames(gr),
										genome = species,
										data = t(meth_mat),
										type = "heatmap",
										showSampleNames = FALSE,
										gradient = c("blue", "white", "red"),
										size = 0.3*ncol(meth_mat),
										col = NA,
										panelFun = function() {grid.text("methylation", 0, unit(1, "npc") - unit(2, "mm"), just = c("left", "top"))},))
	} else {
		for(t in unique(factor)) {
			mat = meth_mat[, factor == t]
			trackList = pushTrackList(trackList, DataTrack(name = t,
										start = start(gr),
										end = end(gr),
										chromosome = seqnames(gr),
										genome = species,
										data = t(mat),
										type = "heatmap",
										showSampleNames = FALSE,
										gradient = c("blue", "white", "red"),
										size = 0.3*ncol(mat),
										col = NA,
										panelFun = local({t = t; function() grid.text(qq("methylation, @{t}"), 0, unit(1, "npc") - unit(2, "mm"), just = c("left", "top"))})
									))
		}
	}
	
	### CpG density per 100bp
	qqcat("add cpg density to gviz tracks...\n")
	segment = seq(gm_site[1], gm_site[length(gm_site)], by = 100)
	start = segment[-length(segment)]
	end = segment[-1]-1
	num = sapply(seq_along(start), function(i) sum(gm_site >= start[i] & gm_site <= end[i]))
	trackList = pushTrackList(trackList, DataTrack(name = "#CpG\nper 100bp",
		                            start = start,
		                            end = end,
		                            chromosome = rep(chr, length(start)),
									genome = species,
									data = num,
									col = "black",
									type = "hist",
									rotate.title = TRUE,
									size = 1,
									col.histogram = "orange",
									fill = "orange",
									panelFun = function() {grid.text("CpG density, window = 100bp", 0, unit(1, "npc") - unit(2, "mm"), just = c("left", "top"))},))
	
	qqcat("add other genomic features to gviz tracks...\n")
	gf_name = names(gf_list)
	for(i in seq_along(gf_list)) {
		trackList = pushTrackList(trackList, constructAnnotationTrack(gf_list[[i]], chr, name = gf_name[i], rotate.title = TRUE, start = gene_start, end = gene_end, size = 0.5,
			panelFun = local({gf_name = gf_name[i]; function() grid.text(gf_name, 0, unit(0.5, "npc"), just = c("left", "center"))})))
	}

	# show mean signal in each subgroup
	if(!is.null(hm_list)) {
		# hm_list is a list of list
		# mark->sid->gr
		all_colors = brewer.pal(8, "Set2")
		hm_name = names(hm_list)
		for(i in seq_along(hm_list)) {
			single_hm_list = hm_list[[i]]
		
			qqcat("add histome modification (@{hm_name[i]}) to gviz tracks...\n")
			single_hm_list2 = lapply(single_hm_list, function(gr) {
				gr = gr[seqnames(gr) == chr]
				l = start(gr) > gene_start & end(gr) < gene_end
				gr[l]
			})

			hm_merged = NULL
			for(j in seq_along(single_hm_list2)) {
				if(length(single_hm_list2[[j]])) hm_merged = rbind(hm_merged, as.data.frame(single_hm_list2[[j]]))
			}
			hm_merged = GRanges(seqnames = hm_merged[[1]], ranges = IRanges(hm_merged[[2]], hm_merged[[3]]))
			if(length(hm_merged) > 0) {
				segments = as(coverage(hm_merged), "GRanges")
				# covert to matrix
				hm_mat = matrix(0, nrow = length(single_hm_list), ncol = length(segments))
				rownames(hm_mat) = names(single_hm_list)
				for(j in seq_along(single_hm_list2)) {
					mtch = as.matrix(findOverlaps(segments, single_hm_list2[[j]]))
					hm_mat[j, mtch[, 1]] = single_hm_list2[[j]][mtch[, 2]]$density
				}
				segments = suppressWarnings(c(segments, GRanges(chr, ranges = IRanges(gene_end - 100, gene_end), score = 0)))
				
				if(is.null(factor)) {
						mat = cbind(hm_mat, rep(0, nrow(hm_mat)))
						# mat[1, ncol(mat)] = max(hm_mat)
						mean_signal = colMeans(mat)
						trackList = pushTrackList(trackList, DataTrack(name = hm_name[i],
													start = start(segments),
													end = end(segments),
													chromosome = seqnames(segments),
													genome = species,
													data = mean_signal,
													type = "hist",
													size = 1,
													ylim = c(0, max(mean_signal)),
													col.histogram = all_colors[i],
													fill = all_colors[i],
													panelFun = local({hm_name = hm_name[i]; function() grid.text(hm_name, 0, unit(1, "npc") - unit(2, "mm"), just = c("left", "top"))})))
				} else {
					mean_signal_list = list()
					for(t in unique(factor)) {
						mat = hm_mat[rownames(hm_mat) %in% sample_id[factor == t], , drop = FALSE]
						mat = cbind(mat, rep(0, nrow(mat)))
						# mat[1, ncol(mat)] = max(hm_mat)
						mean_signal_list[[t]] = colMeans(mat)
					}
					ylim = c(0, max(unlist(mean_signal_list)))
					for(t in unique(factor)) {
						mat = hm_mat[rownames(hm_mat) %in% sample_id[factor == t], , drop = FALSE]
						mat = cbind(mat, rep(0, nrow(mat)))
						# mat[1, ncol(mat)] = max(hm_mat)
						mean_signal = colMeans(mat)

						trackList = pushTrackList(trackList, DataTrack(name = qq("@{hm_name[i]}\n@{t}"),
													start = start(segments),
													end = end(segments),
													chromosome = seqnames(segments),
													genome = species,
													data = mean_signal,
													type = "hist",
													size = 1,
													ylim = ylim,
													col.histogram = all_colors[i],
						                            fill = all_colors[i],
						                            panelFun = local({hm_name = hm_name[i]; t = t; function() grid.text(qq("@{hm_name}, @{t}"), 0, unit(1, "npc") - unit(2, "mm"), just = c("left", "top"))})))
					}
				}
			}
		}
	}

	qqcat("draw gviz plot...\n")
	plotTracks(trackList, from = gene_start, to = gene_end, chromosome = chr, main = "", cex.main = 1, showTitle = FALSE)

	#grid.text(paste(gf_name, collapse = "\n"), x = unit(4, "mm"), y = unit(4, "mm"), just = c("left", "bottom"), gp = gpar(fontsize = 8))
		
	rm(list = ls())
	gc()

	return(invisible(NULL))
}

pushTrackList = function(trackList, track) {
	if(!is.null(track)) {
		trackList[[length(trackList) + 1]] = track
	}
	return(trackList)
}

constructAnnotationTrack = function(gr, chr, name = NULL, genome = "hg19", start = 0, end = Inf, ...) {
	gr2 = gr[seqnames(gr) == chr]
	gr2 = gr2[end(gr2) > start & start(gr2) < end]

	if(length(gr2)) {

		AnnotationTrack(name = name,
		                start = start(gr2),
		                end = end(gr2),
		                chromosome = seqnames(gr2),
		                genome = genome, 
		                stacking = "dense",
		                showTitle = TRUE, 
		                height = unit(5, "mm"),
		                ...)
	} else {
		NULL
	}
}

