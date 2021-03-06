pop_name <- function(x="", pop="") {

	return(sprintf("%s__pop_%s" ,x, pop))

}


add_pop_to_input <- function(input, pop, names_var_pop) {


	for(name_var_pop in names_var_pop){

		input$name <- str_replace_all(input$name, sprintf("\\b%s\\b",name_var_pop), pop_name(name_var_pop, pop))							

		if(!is.null(input$transformation)){
			input$transformation <- str_replace_all(input$transformation, sprintf("\\b%s\\b",name_var_pop), pop_name(name_var_pop, pop))							
		}

		if(!is.null(input$to_resource)){
			input$to_resource <- str_replace_all(input$to_resource, sprintf("\\b%s\\b",name_var_pop), pop_name(name_var_pop, pop))							
		}


	}	

	# pick prior if necessary
	if(!is.null(names(input$prior)) && pop%in%names(input$prior)){
		input$prior <- input$prior[[pop]]
	}

	# pick value if necessary
	if(!is.null(names(input$value)) && pop%in%names(input$value)){
		input$value <- input$value[[pop]]
	}

	if(length(input$value)>1){
		stop("Too many input value for ", sQuote(input$name))
	}

	
	return(input)

}


add_pop_to_reaction <- function(reaction, pop, names_var_pop) {

	for(names_pop_input in names_var_pop){

		# change from
		reaction$from <- str_replace_all(reaction$from, sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				
		
		# change to
		names_to <- names(reaction$to)
		reaction$to <- str_replace_all(reaction$to, sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				
		if(!is.null(names_to)){
			# split reaction
			names(reaction$to) <- str_replace_all(names_to, sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				

		}
		
		# change rate
		if(!is.null(names(reaction$rate))){
			reaction$rate <- reaction$rate[pop]
		}

		if(length(reaction$rate)!=1){
			stop("Wrong specification of reaction rate: ", sQuote(reaction$rate))
		}

		reaction$rate <- str_replace_all(reaction$rate, sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				
		

		if(!is.null(reaction$accumulators)){
			# change accumulators
			reaction$accumulators[[1]] <- str_replace_all(reaction$accumulators[[1]], sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				
		}

		if(!is.null(reaction$white_noise)){
			# change white noise
			reaction$white_noise$name <- str_replace_all(reaction$white_noise$name, sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				
			reaction$white_noise$sd <- str_replace_all(reaction$white_noise$sd, sprintf("\\b%s\\b",names_pop_input), pop_name(names_pop_input, pop))				
		}

	}	

	return(reaction)

}




add_pop_to_observation <- function(observation, pop, names_var_pop) {

	for(name_var_pop in names_var_pop){

		observation$name <- str_replace_all(observation$name, sprintf("\\b%s\\b",name_var_pop), pop_name(name_var_pop, pop))							
		observation$mean <- str_replace_all(observation$mean, sprintf("\\b%s\\b",name_var_pop), pop_name(name_var_pop, pop))							
		
		if(!is.null(observation$sd)){
			observation$sd <- str_replace_all(observation$sd, sprintf("\\b%s\\b",name_var_pop), pop_name(name_var_pop, pop))										
		}

	}	

	return(observation)

}




make_pop_struct <- function(pop, inputs, reactions, observations, names_shared_inputs=NULL, erlang_shapes=NULL) {

	if(0){

		pop <- pop
		inputs <- SEIRD_inputs
		reactions <- SEIRD_reactions
		observations <- SEIRD_observations
		names_shared_inputs <- names_shared_inputs
		erlang_shapes <- Erlang_shapes

	}

	# struct input
	names_var_pop <- setdiff(get_name(inputs), names_shared_inputs)

	inputs_pop <- purrr::map(inputs, function(input) {

		input_pop <- purrr::map(pop, add_pop_to_input, input=input, names_var_pop=names_var_pop)

	}) %>% unlist(recursive = FALSE) %>% unique

	# inputs_pop %>% get_name %>% sort

	# struct reactions
	## add accumulators to names_var_pop
	names_accumulators_pop <- get_element(reactions, "accumulators") %>% unlist %>% unique %>% setdiff(names_shared_inputs)
	names_var_pop <- c(names_var_pop, names_accumulators_pop)

	reactions_pop <- purrr::map(reactions, function(reaction) {

		reaction_pop <- purrr::map(pop, add_pop_to_reaction, reaction=reaction, names_var_pop=names_var_pop)

	}) %>% unlist(recursive = FALSE) %>% unique

	# struct observation
	## add obs names to names_var_pop
	names_obs_pop <- get_name(observations) %>% unlist %>% unique %>% setdiff(names_shared_inputs)
	names_var_pop <- c(names_var_pop, names_obs_pop)

	observations_pop <- purrr::map(observations, function(observation) {

		observation_pop <- purrr::map(pop, add_pop_to_observation, observation=observation, names_var_pop=names_var_pop)

	}) %>% unlist(recursive = FALSE) %>% unique


	# struct erlang
	if(is.list(erlang_shapes) && is.null(names(erlang_shapes))){
		stop("List of erlang_shapes need pop names", sQuote(erlang_shapes))
	} else if (is.atomic(erlang_shapes)){
		erlang_shapes <- rep(list(erlang_shapes), length(pop))
		names(erlang_shapes) <- pop
	}

	df_erlang_shapes <- purrr::map_dfr(erlang_shapes, function(x) {data_frame(state = names(x), shape = x)}, .id="pop")

	df_erlang_shapes_pop <- df_erlang_shapes %>% filter(state %in% names_var_pop) %>% mutate(state = pop_name(state, pop)) %>% select(-pop)
	df_erlang_shapes_shared <- df_erlang_shapes %>% filter(!state %in% names_var_pop) %>% select(-pop) %>% distinct
	df_erlang_shapes_pop <- bind_rows(df_erlang_shapes_pop, df_erlang_shapes_shared)

	erlang_shapes_pop <- df_erlang_shapes_pop$shape
	names(erlang_shapes_pop) <- df_erlang_shapes_pop$state

	return(list(inputs=inputs_pop, reactions=reactions_pop, observations=observations_pop, erlang_shapes=erlang_shapes_pop))

}