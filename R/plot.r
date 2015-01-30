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
plot_X <- function(ssm, path=NULL, id=NULL, stat=c("none","mean","median"), hat=NULL, scales="free_y", fit_only=FALSE) {

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

	# any stat?
	if(stat!="none"){

		stat <- ifelse(stat=="median","stats::median",stat)
		dots <- list(sprintf("%s(value)",stat))
		df_stat <- df_X %>% group_by(date, state) %>% summarize_(.dots=setNames(dots,"value"))
	}

	# any hat?
	if(!is.null(hat)){

		prob <- c((1-hat)/2,(1+hat)/2) %>% unique %>% sort 
		dots <- as.list(sprintf("stats::quantile(value, %s, type=1)",prob))	
		hat_label <- paste0(sort(hat)*100,"%")
		dots_names <- c(sprintf("lower_%s",rev(hat_label)),sprintf("upper_%s",hat_label))

		df_hat <- df_X %>% group_by(date, state) %>% summarize_(.dots=setNames(dots,dots_names)) %>% ungroup %>% gather(tmp, value, -date, -state) %>% separate(tmp,c("hat","level"),sep="_") %>% spread(hat, value)

	}

	if(!is.null(hat)){
		df_plot <- df_hat
	} else {
		df_plot <- df_X
	}

	df_data <- ssm$data %>% gather(state, value, -date)

	if(fit_only){
		# keep states that match data
		df_plot <- df_plot %>% semi_join(df_data, c("date","state"))
		if(stat!="none"){
			df_stat <- df_stat %>% semi_join(df_data, c("date","state"))			
		}
	}

	p <- ggplot(data=df_plot, aes(x=date)) + facet_wrap(~state, scales=scales)

	if(is.null(hat)){
		# plot traj
		p <- p + geom_line(aes(y=value, group=index), alpha=min(c(0.1,10/n_distinct(df_plot$index))))		
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


# plot_theta <- function(ssm) {

# 	# posterior vs prior distribution of parameters

# 	# get the root of the preceding function



# 	# pass ssm to the next
# 	invisible(ssm)

# }


