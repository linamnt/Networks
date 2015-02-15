#
# A module of tools to assist in analyzing networks using igraph.
# 
# Justin W. Kenney
# jkenney9a@gmail.com
# 

library(igraph) #For network functions
library(psych) #For corr_matrix to get R's and p-values
library(brainwaver) #For global efficiency calculation

load_data <- function(csv_file){
  #   Input: CSV file name
  #   
  #   Output: Dataframe containing CSV file
  
  df <- read.csv(file=csv_file, header=TRUE)
  return(df)
}

corr_matrix <- function(df){
  #   Input: Dataframe with headers as titles (brain regions)
  #   
  #   Output: Two dataframes corresponding to 1) all pairwise Pearson 
  #   correlations and 2) all associated un-adjusted p-values


  corr <- corr.test(df, adjust='none')
  df_corr <- as.data.frame(corr['r'])
  df_pvalue <- as.data.frame(corr['p'])
  
  return(list("corr" = df_corr,"pvalue" = df_pvalue))
}

corr_matrix_threshold <- function(df, threshold=0.01){
  #   Input: Dataframe with headers as titles (brain regions) of counts etc.
  #           p-value threshold
  #   
  #   Output: Dataframe of correlations thresholded at p < alpha
  #   
  #   NOTE: Removes diagonals and negative correlations
  
  dfs <- corr_matrix(df)
  df_corr <- dfs[['corr']]
  df_pvalue <- dfs[['pvalue']]
  
  #apply p-value threshold to correlation matrix
  df_corr[mapply(">", df_pvalue, threshold)] <- 0
  
  #remove diagonals (may not be necessary when using igraph...)
  df_corr[mapply("==", df_corr, 1)] <- 0
  
  #remove negative correlations
  df_corr[mapply("<", df_corr, 0)] <- 0
  
  return(df_corr)
}

CSV_to_igraph <- function(CSV_file, thresh=0.01){
  #Input: CSV_file of counts etc., p-value threshold
  #
  #Output: igraph graph object
  
  df <- load_data(CSV_file)
  df_G <- corr_matrix_threshold(df,threshold=thresh)
  names(df_G) <- gsub("r.","",colnames(df_G), fixed=TRUE) #Remove ".r" from node names
  
  #Change ... to -; for some reason when R imports "-" it turns it into "..."
  names(df_G) <- gsub("...","-",colnames(df_G), fixed=TRUE) 
  
  G <- graph.adjacency(as.matrix(df_G), mode="undirected",
                       weighted=TRUE)
  
  return(G)
}

get_centrality_measures <-function(G){
  # Input: An igraph graph
  #
  # Output: A dataframe of centrality measures:
  # Degree, betweenness, eigenvector, closeness, 
  # transitivity (~clustering coefficient), nodal efficiency
  # NOTE: nodal efficiency makes use of weights if they exist
  
  degree <- degree(G)
  between <- betweenness(G, normalized=TRUE, weights=NULL)
  eigenvector <- evcent(G)
  close <- closeness(G)
  trans <- transitivity(G,type="local")
  
  #Need to pull out matrices for efficiency calculations
  adj_mat <- as.matrix(get.adjacency(G))
  weight_mat <- as.matrix(get.adjacency(G, attr='weight'))
  efficiency <- global.efficiency(adj_mat, weight_mat)
  
  output <- data.frame("degree" = degree, "betweenness" = between, 
                       "eigenvector" = eigenvector[[1]], "closeness" = close,
                      "efficiency" = efficiency[[1]], "transitivity" = trans)
  
  return(output)
}

GC_size <- function(G){
  #Input: igraph graph
  #
  #Output: size of giant component
  
  return(max(clusters(G)[[2]]))
}

Global_efficiency <- function(G, weighted=TRUE){
  #Input: igraph graph
  #
  #Output: efficiency; 
  #NOTE: default uses weighted matrix and assumes 
  #the attribute is called "weight" in the graph.
  
  adj_mat <- as.matrix(get.adjacency(G))
  
  if(weighted==TRUE){
    weight_mat <- as.matrix(get.adjacency(G, attr='weight'))
    efficiency <- global.efficiency(adj_mat, weight_mat)
  } else{
    efficiency <- global.efficiency(adj_mat, adj_mat)
  }
    
  return(mean(efficiency[[1]]))
}

Rand_graph_stats <- function(G, iterations = 100, degree_dist=TRUE){
  #Input: igraph graph, wehther or not random graphs should have
  #same degree distribution as input graph.
  #
  #Output: Equivalent random graph statistics and stdev in a df:
  #Transitivity (very closely related to clustering coefficient)
  #Global efficiency
  
  TR <- c() #Transitivity
  GE <- c() #global efficiency (GE)
  
  if(degree_dist == TRUE){
    #Get rid of degree zero nodes b/c this causes issues with the
    #generation of random graphs using the "vl" algorithm
    G_1 <- delete.vertices(G, which(degree(G) == 0))
    degrees <- degree(G_1)
    
    #Get number of zero degree nodes
    zero_d <- length(degree(G)) - length(degrees)
    
    for(i in 1:iterations){
      RG <- degree.sequence.game(degree(G_1), method='vl')
      TR <- append(TR, transitivity(RG, type="global"))
      #Add back in zero degree nodes to get efficiency of whole graph
      GE <- append(GE, Global_efficiency(RG + zero_d, weighted=FALSE))
      } 
    } else{
  
  if(degree_dist == FALSE){
    n <- length(vertex.attributes(G)[[1]]) #number of nodes
    m <- length(edge.attributes(G)[[1]]) #number of edges
    for(i in 1:iterations){
      RG <- erdos.renyi.game(n, m, type="gnm")
      TR <- append(TR, transitivity(RG, type="global"))
      GE <- append(GE, Global_efficiency(RG, weighted=FALSE))
      }
    }
  }
      
  TR_out <- c(mean(TR), sd(TR))
  GE_out <- c(mean(GE), sd(GE))
  
  return(data.frame("Transitivity" = TR_out, 
                    "Global efficiency" = GE_out,
                    row.names = c("Average", "stdev")))
}