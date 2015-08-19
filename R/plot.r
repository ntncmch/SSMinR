
#'Interactive display of SSM model
#'
#'This function displays the SSM model as a force network or a diagramme in a web browser, allowing for manipulation.
#' @param ssm a \code{\link{ssm}} object
#' @param collapse_erlang logical, if \code{TRUE} erlang compartments are collapsed into a single compartment to improve visibility.
#' @param display logical, if \code{TRUE} erlang compartments are collapsed into a single compartment to improve visibility.
#' @export
#' @import networkD3 DiagrammeR
plot_model <- function(ssm, collapse_erlang = TRUE, display=c("network","diagramme"), engine = "dot") {

	display <- match.arg(display)

	from <- get_element(ssm$reactions, "from")
	to <- get_element(ssm$reactions, "to")
	rate <- get_element(ssm$reactions, "rate")
	network_data <- data_frame(reaction= seq_along(from), from, to, rate)

	if(collapse_erlang){

		erlang_shapes <- ssm$erlang_shapes
		erlang_states <- names(erlang_shapes)

		remove_to <- sapply(names(erlang_shapes), function(erlang_state) erlang_state %>% erlang_name(2:(erlang_shapes[erlang_state]))) %>% unlist
		
		revalue_from <- erlang_name(erlang_states, 1)
		names(revalue_from) <- sapply(names(erlang_shapes), function(erlang_state) erlang_state %>% erlang_name((erlang_shapes[erlang_state]))) %>% unlist

		revalue_sum <- erlang_states
		names(revalue_sum) <- sapply(names(erlang_shapes), function(erlang_state) erlang_state %>% erlang_name(1:(erlang_shapes[erlang_state])) %>% paste(collapse=" + ") %>% protect) %>% unlist
		
		network_data <- network_data %>% mutate(from=revalue(from, revalue_from)) %>% filter(!to%in%remove_to) %>% gather(type, state, -c(reaction, rate)) %>% 
		mutate(state=str_replace_all(state, "__erlang[0-9]+", "")) %>% spread(type, state) 
		
		# TODO: collapse erlang rates, create a function for this		
		# rate = rate %>% str_replace_all(names(revalue_sum), revalue_sum)) 

	}

	if(display=="diagramme"){

		node_statement <- network_data %>% .[c("from","to")] %>% unlist %>% unique %>% paste(collapse="; ")
		if(collapse_erlang){
			message("collapse_erlang for reaction rates not yet implemented. Use ", sQuote("collapse_erlang=FALSE"), " to display all states/rates", call.=FALSE)
			edge_statement <- network_data %>% unite(edge, c(from, to), sep="->") %>% select(edge) %>% unlist %>% unname %>% paste(collapse=" ")			
		} else {
			edge_statement <- network_data %>% unite(edge, c(from, to), sep="->") %>% mutate(edge = sprintf("%s [label = \" %s\"]", edge, rate)) %>% select(edge) %>% unlist %>% unname %>% paste(collapse=" ")			
		}

		gviz_cmd <- sprintf("
			digraph circles {

 		 # a 'graph' statement
				graph [overlap = true, fontsize = 10]

 		 # several 'node' statements
				node [shape = circle,
				fontname = Helvetica,
				style = filled,
				color = grey,
				fillcolor = steelblue]
				%s

 		 # several 'edge' statements
				edge[color = grey]
				%s
			}
			", node_statement, edge_statement)

		return(grViz(gviz_cmd, engine = engine))

	}


	if(display=="network"){

		return(simpleNetwork(network_data, Source="from", Target="to", zoom = TRUE))
	}

}


#'Plot states
#'
#'Function to plot state trajectories contained in the \code{X_*.csv} files generated by SSM. Pipeable.
#' @param  path character, where to find \code{X_*.csv}. If \code{NULL} (default), use the \code{path} of the last block (e.g. \code{/pmcmc}).
#' @param  id numeric, indicate which \code{X_*.csv} to choose. If \code{NULL} (default), use the \code{id} of the last block (default to 0 in SSM).
#' @param  stat character, whether to plot a summary statistics of the state. Either \code{"mean"} or \code{"median"}. Default to \code{"none"}.
#' @param  hat numeric, vector of credible intervals, between 0 and 1, e.g. \code{hat=c(0.5, 0.95)} for 50 and 95\% credible intervals.
#' @param  scales character, should scales be \code{"fixed"}, \code{"free"}, or free in one dimension: \code{"free_x"}, \code{"free_y"} (the default).
#' @param  fit_only logical, whether to show only the fit to the data.
#' @inheritParams call_ssm
#' @export
#' @import ggplot2 tidyr dplyr
#' @seealso \code{\link{plot_theta}}
#' @return a \code{ssm} object updated with latest SSM output and ready to be piped into another SSM block.
plot_X <- function(ssm, path=NULL, id=NULL, stat=c("none","mean","median"), hat=NULL, scales="free_y", fit_only=FALSE, collapse_erlang=TRUE) {

	stat <- match.arg(stat)

	if(is.null(path)){

		path <- ssm$hidden$last_path
		
		if(is.null(path)){
			stop("Argument",sQuote("path"),"required", call.=FALSE)	
		}
	}

	if(!is.null(id)){

		df_X <- sprintf("X_%s.csv",id) %>% file.path(path,.) %>% read.csv

	} else {

		# search for all X_* in path
		X_files <- list.files(path) %>% grep("X_*",.,value=TRUE)

		if(length(X_files)==0){
			stop("No X files in directory", dQuote(path),"..... The Truth is Out There")
		}

		if(length(X_files)>1){
			
			# if more than one, take ssm$summary$id. If missing, send error
			id <- ssm$summary[["id"]]
			if(is.null(id)){
				stop("Use numeric argument",sQuote("id"),"to select one file among:",sQuote(X_files))
			}
			X_files <- sprintf("X_%s.csv",id)

		}

		df_X <- file.path(path,X_files) %>% read.csv

	}
	
	# tidy
	df_X <- df_X %>% mutate(date=as.Date(date)) %>% gather(state, value, -date, -index)  

	if(collapse_erlang){

		df_X <- collapse_erlang(df_X)
		
	}

	# separate pop only if collapse_erlang. Otherwise we loose erlang order as always last.
	if(collapse_erlang && any(str_detect(df_X$state, pop_name()))){

		df_X_pop <- df_X %>% filter(str_detect(state, pop_name())) %>% separate(state, c("state","pop"), sep=pop_name())
		df_X <- df_X %>% filter(!str_detect(state, pop_name())) %>% bind_rows(df_X_pop) %>% arrange(index, date, pop, state)

	}

	# any stat?
	if(stat!="none"){

		stat <- ifelse(stat=="median","stats::median",stat)
		dots_summarize <- list(sprintf("%s(value)",stat))
		dots_group_by <- setdiff(names(df_X), c("value","index"))
		df_stat <- df_X %>% group_by_(.dots=dots_group_by) %>% summarize_(.dots=setNames(dots_summarize,"value"))
	}

	# any hat?
	if(!is.null(hat)){

		prob <- c((1-hat)/2,(1+hat)/2) %>% unique %>% sort 
		dots_summarize <- as.list(sprintf("stats::quantile(value, %s, type=1)",prob))	
		dots_group_by <- setdiff(names(df_X), c("value","index"))

		hat_label <- paste0(sort(hat)*100,"%")
		dots_names <- c(sprintf("lower_%s",rev(hat_label)),sprintf("upper_%s",hat_label))

		df_hat <- df_X %>% group_by_(.dots=dots_group_by) %>% summarize_(.dots=setNames(dots_summarize,dots_names)) %>% ungroup %>% gather(tmp, value, matches("lower|upper")) %>% separate(tmp,c("hat","level"),sep="_") %>% spread(hat, value)

	}

	if(!is.null(hat)){
		df_plot <- df_hat
	} else {
		df_plot <- df_X
	}

	df_data <- ssm$data %>% rename(state=time_series)

	if(collapse_erlang && any(str_detect(df_data$state, pop_name()))){

		df_data_pop <- df_data %>% filter(str_detect(state, pop_name())) %>% separate(state, c("state","pop"), sep=pop_name())
		df_data <- df_data %>% filter(!str_detect(state, pop_name())) %>% bind_rows(df_data_pop) %>% arrange(date, pop, state)

	}

	by_names <- intersect(names(df_data), names(df_plot)) %>% setdiff("value")
	df_data <- df_data %>% semi_join(df_plot, by=by_names)

	if(fit_only){

		# keep states that match data
		df_plot <- df_plot %>% semi_join(df_data, by_names)
		if(stat!="none"){
			df_stat <- df_stat %>% semi_join(df_data, by_names)			
		}
	}

	p <- ggplot(data=df_plot, aes(x=date)) + facet_wrap(pop~state, scales=scales)

	if(is.null(hat)){
		# plot traj

		# choose alpha
		n_index <- n_distinct(df_plot$index)
		alpha <- ifelse(n_index > 10, min(c(0.1,10/n_index)), 1)
		p <- p + geom_line(aes(y=value, group=index), alpha=alpha)		
	} else {

		alpha_values <- seq(0.2,0.6,len=length(hat_label)) %>% rev
		names(alpha_values) <- hat_label
		p <- p + geom_ribbon(aes(ymin=lower, ymax=upper, alpha=level)) + scale_alpha_manual("Level", values=alpha_values)
	}

	if(stat!="none"){
		# add stat
		p <- p + geom_line(data=df_stat, aes(y=value))
	}

	p <- p + geom_point(data=df_data, aes(y=value))
	
	print(p)

	# add to ssm plot
	ssm$plot$X <- p

	invisible(ssm)
}


#'Plot data
#'
#'Plot the data of your \code{ssm} object.
#' @inheritParams call_ssm
#' @inheritParams plot_X
#' @export
#' @import ggplot2 tidyr
plot_data <- function(ssm, scales="free_y") {

	if(!inherits(ssm,"ssm")){
		stop(sQuote("ssm"),"is not an object of class ssm")
	}

	df_data <- ssm$data %>% rename(state=time_series)

	if(any(str_detect(df_data$state, pop_name()))){

		df_data_pop <- df_data %>% filter(str_detect(state, pop_name())) %>% separate(state, c("state","pop"), sep=pop_name())
		df_data <- df_data %>% filter(!str_detect(state, pop_name())) %>% bind_rows(df_data_pop) %>% arrange(date, pop, state)

	}


	p <- ggplot(data, aes(x=date, y=value)) + facet_wrap(pop~state, scales=scales)
	p <- p + geom_bar(stat="identity")
	print(p)

	# add to ssm plot
	ssm$plot$data <- p

	invisible(ssm)

}

# plot_theta <- function(ssm) {

# 	# posterior vs prior distribution of parameters

# 	# get the root of the preceding function



# 	# pass ssm to the next
# 	invisible(ssm)

# }


