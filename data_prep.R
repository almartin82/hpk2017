## ------------------------------------------------------------------------

today = Sys.Date()


## ----message = FALSE, warning = FALSE, error = FALSE---------------------

library(readr)
library(tidyverse)


## ----message = FALSE, warning = FALSE------------------------------------

hpk_2017 <- readr::read_csv(
  file = 'https://s3.amazonaws.com/hpk/hpk_2017.csv', na = ('-')
) %>%
  dplyr::filter(date < today)

hpk_2017_rosters <- readr::read_csv(
  file = 'https://s3.amazonaws.com/hpk/hpk_2017_rosters.csv', na = ('-')
) %>%
  dplyr::filter(date < today)
  
owners <- readr::read_csv(file = "http://hpk.s3-website-us-east-1.amazonaws.com/all_owners.csv")


## ----abbrevs-------------------------------------------------------------

short_names <- data.frame(
  team_key = c(
    '370.l.107101.t.1', '370.l.107101.t.2', '370.l.107101.t.3',
    '370.l.107101.t.4', '370.l.107101.t.5', '370.l.107101.t.6',
    '370.l.107101.t.7', '370.l.107101.t.8', '370.l.107101.t.9',
    '370.l.107101.t.10', '370.l.107101.t.11', '370.l.107101.t.12'
  ),
  owner = c('bench', 'omar', 'saud', 
            'eric', 'whet', 'mcard',
            'mintz', 'czap', 'ptb', 
            'carter', 'mo', 'alm'
  ),
  stringsAsFactors = FALSE
)


## ----clean---------------------------------------------------------------


clean_rows <- function(df) {
  df <- df[!is.na(df$value), ]
  df <- df[!df$value == "", ]
  return(df)
}


clean_values <- function(df) {
  
  hpk1 <- df %>% dplyr::filter(!stat_name == 'AVG' | is.na(stat_name))
  
  hpk2 <- df %>% dplyr::filter(stat_name == 'AVG') 
  
  avg <- hpk2 %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      value = eval(parse(text = value))
    )
  
  h  <- hpk2
  ab <- hpk2
  h$value <- matrix(
    unlist(strsplit(h$value, split = '/')), 
    ncol = 2, byrow = TRUE
  )[,1]
  ab$value <- matrix(
    unlist(strsplit(ab$value, split = '/')), 
    ncol = 2, byrow = TRUE
  )[,2]
  h$stat_id <- NA
  ab$stat_id <- NA
  h$stat_name <- 'H'
  ab$stat_name <- 'AB'
  
  avg$value <- round(avg$value, 5)
    
  cleaned <- rbind(hpk1, h, ab, avg)
  
  cleaned$value <- as.numeric(cleaned$value)
  
  return(cleaned)
}


stat_metadata <- function(df) {
  
  meta_df <- data.frame(
    stat_name = c(
      "OBP", "R", "RBI", "SB", "TB", "AVG", "AB", "H",
      "ERA", "WHIP", "W", "SV", "K", 
      "IP", "Runs Allowed", "WH Allowed"),
    hit_pitch = c(rep("hit", 8), rep("pitch", 8))
  )
  
  df %>% dplyr::left_join(
    meta_df,
    by = 'stat_name'
  )
}

true_era_whip <- function(df) {
  #grab the target rows
  desired_rows <- c('ERA', 'WHIP', 'IP')
  
  target <- df %>% dplyr::filter(
    stat_name %in% desired_rows
  )
  
  #just IP
  ip_df <- target %>% 
    dplyr::filter(stat_name == 'IP') 
  names(ip_df)[names(ip_df) == 'value'] <- "IP"
  
  #convert and clean IP
  #mlb codes 1 out as .1, 2 outs as .2.  replace with 0.333, 0.667
  ip_df$IP <- gsub('.1', '.333', ip_df$IP, fixed = TRUE)
  ip_df$IP <- gsub('.2', '.667', ip_df$IP, fixed = TRUE)
  ip_df$IP <- as.numeric(ip_df$IP)

  #era and whip solo
  era_df <- target %>%
    dplyr::filter(stat_name == 'ERA')
  
  whip_df <- target %>%
    dplyr::filter(stat_name == 'WHIP')
  
  #join to ip
  era_df <- era_df %>% dplyr::inner_join(
    ip_df[, c('team_key', 'date', 'IP')],
    by = c("team_key", "date")
  )
  #weird phantom 0IP / ERA NA
  era_df <- era_df[!is.na(era_df$value), ]
  
  whip_df <- whip_df %>% dplyr::inner_join(
    ip_df[, c('team_key', 'date', 'IP')],
    by = c("team_key", "date")
  )
  whip_df <- whip_df[!is.na(whip_df$value), ]
  
  #recover actual runs allowed and walks hits given up
  era_df$value <- round((as.numeric(era_df$value) / 9) * era_df$IP, 0)
  era_df$stat_name <- 'Earned Runs Allowed'
  era_df$stat_id <- NA
  era_df <- era_df %>% dplyr::select(-IP)
  era_df$date <- as.Date(era_df$date)
  era_df$value <- as.character(era_df$value)

  whip_df$value <- round(as.numeric(whip_df$value) * whip_df$IP, 0)
  whip_df$stat_name <- 'WH Allowed'
  whip_df$stat_id <- NA
  whip_df <- whip_df %>% dplyr::select(-IP)
  whip_df$date <- as.Date(whip_df$date)
  whip_df$value <- as.character(whip_df$value)
  
  dplyr::bind_rows(dplyr::tbl_df(df), era_df, whip_df)
}


infer_pa <- function(reported_obp, reported_h, reported_ab) {
  if (reported_obp == 0) {
    return(list(0,0))
  }
  pa <- c(1:60)
  combs <- expand.grid(pa, pa)
  names(combs) <- c('ob', 'pa')
  combs$obp <- round(combs$ob / combs$pa, 3)
  
  #PA always bigger than AB, ob > h
  possible <- combs %>% dplyr::filter(
    pa >= quote(reported_ab) &
    ob >= quote(reported_h) &
    obp == quote(reported_obp)
  )
  
  if (nrow(possible) == 0) {
    print('obp pa inference problem :(')
   
    print(paste0('AB:', reported_ab))
    print(paste0('H:', reported_h))
    print(paste0('OBP:', reported_obp))
  }
  possible$pa_diff <- (possible$pa - reported_ab)
  
  #return
  list(
    possible[possible$pa_diff == min(possible$pa_diff), 'ob'][1],
    possible[possible$pa_diff == min(possible$pa_diff), 'pa'][1]
  )
}


clean_obp <- function(df) {
  
  not_obp <- df %>% dplyr::filter(!stat_name == 'OBP')

  #need three things: obp, avg, and ab
  is_obp <- df %>% dplyr::filter(stat_name == 'OBP')
  
  h <- df %>% dplyr::filter(stat_name == 'H')
  h <- h[, c('value', 'team_key', 'date')]
  names(h)[names(h) == 'value'] <- 'H'
  
  ab <- df %>% dplyr::filter(stat_name == 'AB')
  ab <- ab[, c('value', 'team_key', 'date')]
  names(ab)[names(ab) == 'value'] <- 'AB'

  munge <- is_obp %>%
    dplyr::left_join(h, by = c('date', 'team_key')) %>%
    dplyr::left_join(ab, by = c('date', 'team_key'))
  
  munge$OB <- NA
  munge$PA <- NA
  munge <- as.data.frame(munge)
  for (i in 1:nrow(munge)) {
    this_pa <- infer_pa(munge[i, 'value'], munge[i, 'H'], munge[i, 'AB'])
    munge[i, 'OB'] <- this_pa[[1]]
    munge[i, 'PA'] <- this_pa[[2]]
  }
  
  ob <- munge %>%
    dplyr::select(
      stat_id, OB, date, team_key, manager, owner, team_name, stat_name, hit_pitch
    )
  names(ob)[names(ob) == 'OB'] <- 'value'
  ob$stat_name <- 'OB'
  ob$stat_id <- NA
  
  pa <- munge %>%
    dplyr::select(
      stat_id, PA, date, team_key, manager, owner, team_name, stat_name, hit_pitch
    )
  names(pa)[names(pa) == 'PA'] <- 'value'
  pa$stat_name <- 'PA'
  pa$stat_id <- NA

  rbind(ob, pa, not_obp, is_obp)
}



## ----clean_df------------------------------------------------------------

hpk_2017 <- hpk_2017 %>%
  dplyr::left_join(short_names)


## ------------------------------------------------------------------------
hpk_2017_clean <- hpk_2017 %>%
  clean_rows %>%
  true_era_whip %>%
  clean_values %>%
  stat_metadata %>% 
  clean_obp %>%
  dplyr::tbl_df()

year_min <- hpk_2017 %>%
  dplyr::mutate(
    year = as.numeric(format(as.Date(date), "%Y"))
  ) %>%
  dplyr::group_by(year) %>%
  dplyr::summarize(
    start_date = min(date),
    end_date = max(date)
  ) 

hpk_2017 <- hpk_2017 %>%
  dplyr::mutate(
    year = as.numeric(format(as.Date(date), "%Y"))
  ) %>%
  dplyr::left_join(
    year_min
  ) %>%
  dplyr::mutate(day_of_season = date - start_date) %>%
  dplyr::mutate(days_till_end = end_date - date) %>%
  dplyr::select(
    -year
  )


## ----standings-----------------------------------------------------------

h_points <- function(df) {
  h_total <- df %>% 
    dplyr::filter(
      stat_name %in% c('R', 'RBI', 'SB', 'TB', 'OB', 'PA')
    ) %>% 
    dplyr::group_by(
      team_key, stat_name
    ) %>% 
    dplyr::summarize(
      total_value = sum(as.numeric(value), na.rm = TRUE),
      n = n()
    )
  
  #h conversion here
  h_total <- convert_h_stats(h_total)

  h_points <- h_total %>% 
    dplyr::group_by(stat_name) %>%
    dplyr::mutate(
      rank = rank(total_value)
    ) 

  h_points
}


p_points <- function(df) {
  p_total <- df %>% 
    dplyr::filter(
      stat_name %in% c('W', 'SV', 'K', 'Earned Runs Allowed', 'WH Allowed', 'IP')
    ) %>% 
    dplyr::group_by(
      team_key, stat_name
    ) %>% 
    dplyr::summarize(
      total_value = sum(as.numeric(value)),
      n = n()
    )
  
  #p conversion here
  p_total <- convert_p_stats(p_total)
  
  #some are bad
  p_total$total_value <- ifelse(
    p_total$stat_name %in% c('ERA', 'WHIP'), p_total$total_value * -1,
    p_total$total_value
  )
  
  p_points <- p_total %>% 
    dplyr::group_by(stat_name) %>%
    dplyr::mutate(
      rank = rank(total_value)
    ) 

  p_points
}


p_totals <- function(df) {
  p_points(df) %>%
    dplyr::group_by(team_key) %>%
    dplyr::summarize(
      P = sum(rank)
    )
}


convert_p_stats <- function(df) {
  #non rate vs rate
  non_rate <- df %>%
    dplyr::filter(
      stat_name %in% c('W', 'SV', 'K')
    )
  rate <- df %>%
    dplyr::filter(
      stat_name %in% c('Earned Runs Allowed', 'WH Allowed')
    )
  
  ip <- df %>%
    dplyr::filter(stat_name == 'IP')
  
  names(ip)[names(ip) == 'total_value'] <- 'IP'
  
  #join rate to ip
  rate <- rate %>%
    dplyr::left_join(
      ip %>% dplyr::select(team_key, IP),
      by = 'team_key'
    )
  
  rate$total_value <- rate$total_value / rate$IP
  #ERA on 9 inning scale
  rate$total_value <- ifelse(
    rate$stat_name == 'Earned Runs Allowed', rate$total_value * 9, rate$total_value
  )
  rate$stat_name <- ifelse(
    rate$stat_name == 'Earned Runs Allowed', 'ERA', 'WHIP'
  )
  
  dplyr::bind_rows(rate, non_rate)
}


convert_h_stats <- function(df) {
  #non rate vs rate
  non_rate <- df %>%
    dplyr::filter(
      stat_name %in% c('R', 'RBI', 'SB', 'TB')
    )
  rate <- df %>%
    dplyr::filter(
      stat_name %in% c('OB')
    )
  
  pa <- df %>%
    dplyr::filter(stat_name == 'PA')
  
  names(pa)[names(pa) == 'total_value'] <- 'PA'
  
  #join rate to pa
  rate <- rate %>%
    dplyr::left_join(
      pa[, c('team_key', 'PA')],
      by = 'team_key'
    )
  
  rate$total_value <- rate$total_value / rate$PA
  rate$stat_name <- 'OBP'
  
  dplyr::bind_rows(rate, non_rate)
}


h_totals <- function(df) {
  h_points(df) %>%
    dplyr::group_by(team_key, n) %>%
    dplyr::summarize(
      H = sum(rank)
    )
}


h_table_rank <- function(df) {
  
  df_detail <- h_points(df)
  df_points_wide <- tidyr::spread(df_detail[, c('team_key', 'stat_name', 'rank')], stat_name, rank)
  
  df_total <- h_totals(df)
  
  df_points_wide %>%
    dplyr::left_join(df_total, by = c('team_key')) %>%
    dplyr::arrange(-H)  %>%
    dplyr::left_join(
      owners[ ,c('team_key', 'name')],
      by = 'team_key'
    ) %>%
    dplyr::select(
      team_key, R, RBI, SB, TB, OBP, H
    )
}


h_table_stats <- function(df) {
  
  df_detail <- h_points(df)
  df_stats_wide <- tidyr::spread(
    data = df_detail %>% dplyr::select(team_key, stat_name, total_value),
    stat_name, 
    total_value
  )
  df_stats_wide$OBP <- round(df_stats_wide$OBP, 3)
  
  df_total <- h_totals(df)
  
  df_stats_wide %>%
    dplyr::left_join(df_total) %>%
    dplyr::arrange(-H)  %>%
    dplyr::left_join(
      owners[ ,c('team_key', 'name')],
      by = 'team_key'
    ) %>%
    dplyr::select(
      team_key, R, RBI, SB, TB, OBP, H
    )
}


p_table_rank <- function(df) {
  
  df_detail <- p_points(df)
  df_points_wide <- tidyr::spread(df_detail[, c(1:2, 6)], stat_name, rank)
  
  df_total <- p_totals(df)
  
  df_points_wide %>%
    dplyr::left_join(df_total, by = "team_key") %>%
    dplyr::arrange(-P)  %>%
    dplyr::left_join(
      owners[ ,c('team_key', 'name')],
      by = 'team_key'
    ) %>%
    dplyr::select(
      team_key, W, SV, K, ERA, WHIP, P
    )
}


p_table_stats <- function(df) {
  
  df_detail <- p_points(df)
  df_stats_wide <- tidyr::spread(
    data = df_detail %>% dplyr::select(team_key, stat_name, total_value),
    stat_name, 
    total_value
  )

  df_total <- p_totals(df)
  
  df_stats_wide <- df_stats_wide %>%
    dplyr::left_join(df_total) %>%
    dplyr::arrange(-P)  %>%
    dplyr::left_join(
      owners[ ,c('team_key', 'name')],
      by = 'team_key'
    ) %>%
    dplyr::select(
      team_key, W, SV, K, ERA, WHIP, P
    )
  
  df_stats_wide$ERA <- round(df_stats_wide$ERA * -1, 2)
  df_stats_wide$WHIP <- round(df_stats_wide$WHIP * -1, 3)
  
  df_stats_wide
}

all_table_stats <- function(df) {
  result <- h_table_stats(df) %>% 
    dplyr::left_join(
      p_table_stats(df)
    ) %>%
    dplyr::mutate(
      points = H + P,
      rank = rank(-points)
    ) %>%
    dplyr::arrange(
      rank
    ) %>%
    dplyr::select(
      R, RBI, SB, TB, OBP, H, W, SV, K, ERA, WHIP, P, points, rank
    )

  result
}


all_table_rank <- function(df) {
  result <- h_table_rank(df) %>% 
    dplyr::left_join(
      p_table_rank(df),
      by = c("team_key")
    ) %>%
    dplyr::mutate(
      points = H + P,
      rank = rank(-points, ties.method = 'min')
    ) %>%
    dplyr::arrange(
      rank
    ) %>%
    dplyr::select(
      team_key, R, RBI, SB, TB, OBP, H, W, SV, K, ERA, WHIP, P, points, rank
    )
  
  result
}


best_h <- function(df) {
  stats <- h_table_stats(df)
  ranks <- h_table_rank(df)
  
  result <- stats %>%
    dplyr::left_join(
      ranks,
      by = c('team_key')
    ) 

  
  names(result) <- gsub('.x', '', names(result), fixed = TRUE)
  names(result) <- gsub('.y', '.', names(result), fixed = TRUE)
  
  result %>%
    dplyr::arrange(
      -H
    ) %>%
    dplyr::select_(
      'team_key', 'R', 'RBI', 'SB', 'TB', 'OBP', 'R.', 'RBI.', 'SB.', 'TB.', 'OBP.', 'H'
    )
}


best_p <- function(df) {
  stats <- p_table_stats(df)
  ranks <- p_table_rank(df)
  
  result <- stats %>%
    dplyr::left_join(
      ranks,
      by = c('team_key')
    ) 

  
  names(result) <- gsub('.x', '', names(result), fixed = TRUE)
  names(result) <- gsub('.y', '.', names(result), fixed = TRUE)
  
  result %>%
    dplyr::arrange(
      -P
    ) %>%
    dplyr::select_(
      'team_key',  'W', 'SV', 'K', 'ERA', 'WHIP', 'W.', 'SV.', 'K.', 'ERA.', 'WHIP.', 'P'
    )
}


## ------------------------------------------------------------------------

tag_owner <- function(target_df, owner_df, suppress_key = TRUE) {
  
  orig_names <- names(target_df)
  
  out <- target_df %>%
    dplyr::ungroup() %>%
    dplyr::left_join(owner_df, by = 'team_key')
  
  final_names <- orig_names[!orig_names == 'team_key']
  
  final_names = c(names(owner_df), orig_names)
  if (suppress_key) {
    final_names <- final_names[!final_names == 'team_key']
  }
  
  out <- out %>%
    dplyr::select(one_of(final_names))
  
  return(out)
}


## ------------------------------------------------------------------------

calc_cumulative_stats <- function(df) {
  df %>%
    dplyr::arrange(team_key, stat_name, date) %>%
    dplyr::group_by(team_key, stat_name) %>%
    dplyr::mutate(cumulative_value = cumsum(value))
}

hpk_2017_clean_cumulative <- calc_cumulative_stats(hpk_2017_clean)

## ------------------------------------------------------------------------

hpk_rosters <- read_csv(
  file = file.path('~', 'Google Drive', 'repositories', 'hpk-data', 'hpk_2017_rosters.csv')
)

hpk_starting_rosters <- hpk_rosters %>%
  dplyr::filter(
    played %in% c('C', '1B', '2B', 'SS', '3B', 'OF', 'Util', 'RP', 'SP', 'P')
  )


## ------------------------------------------------------------------------

daily_player_stats_files <- list.files(
#  path = file.path('~', 'Google Drive', 'repositories', 'hpk-data', 'data'),
  path = file.path('daily_player_data'),
  full.names = TRUE
)

daily_player_stat_list <- lapply(daily_player_stats_files, readr::read_csv, na = '-') 

for (i in 1:length(daily_player_stat_list)) {
  this_day <- daily_player_stat_list[[i]]
  
  print(table(this_day$date))
}

daily_player_stats <- dplyr::bind_rows(daily_player_stat_list)


## ------------------------------------------------------------------------

stat_names1 = data.frame(
  'stat_id' = c(6, 65, 3, 7, 13, 16, 23, 4, 50, 28, 32, 42, 26, 27),
  'stat_name' =  c('AB', 'PA', 'AVG', 'R', 'RBI', 'SB', 'TB', 'OBP', 'IP', 'W', 'SV', 'K', 'ERA', 'WHIP'),
  'important' = TRUE
)
stat_names2 = data.frame(
  #0, 1, 2 probably some combination of games started, games played
  
  #H - maybe 8?
  
  #34 probably h allowed
  #39 probably BB allowed
  #36 probably R
  #37 probably ER
  
  'stat_id' = c(0, 8, 15, 34, 39, 41, 58, 59, 36, 37, 18, 20),
  'stat_name' =  c('G', 'H', 'SF', 'H_allowed', 'batters_HBP', 'BB_allowed', 'team', 'league', 'R Allowed', 'Earned Runs Allowed', 'BB', 'HBP'),
  'important' = FALSE
)

stat_names = rbind(stat_names1, stat_names2)

daily_player_stats <- daily_player_stats %>%
  #dplyr::inner_join(stat_names %>% filter(important == TRUE), by = 'stat_id') %>%
  dplyr::left_join(stat_names, by = 'stat_id') %>%
  dplyr::arrange(date, player_key, stat_id) %>%
  #filter out weird character ones
  dplyr::filter(!stat_id %in% c(58, 59)) 

ob_stat <- daily_player_stats %>%
  dplyr::filter(stat_name %in% c('H', 'BB', 'HBP')) %>%
  dplyr::group_by(player_key, date) %>%
  dplyr::summarize(
    value = sum(as.numeric(value), na.rm = TRUE)
  ) %>%
  dplyr::mutate(
    stat_id = NA,
    stat_name = 'OB'
  )

wh_stat <- daily_player_stats %>%
  dplyr::filter(stat_name %in% c('BB_allowed', 'H_allowed')) %>%
  dplyr::group_by(player_key, date) %>%
  dplyr::summarize(
    value = sum(as.numeric(value), na.rm = TRUE)
  ) %>%
  dplyr::mutate(
    stat_id = NA,
    stat_name = 'WH Allowed'
  )

daily_player_stats_topline <- daily_player_stats %>%
  dplyr::filter(important == TRUE) %>%
  dplyr::mutate(value = as.numeric(value)) %>%
  dplyr::select(-important)

daily_player_stats <- dplyr::bind_rows(daily_player_stats_topline, ob_stat, wh_stat)


## ------------------------------------------------------------------------

hpk_starting_rosters <- hpk_starting_rosters %>%
  dplyr::left_join(
    daily_player_stats, by = c('player_key', 'date')
  )


## ----eval = FALSE, warning = FALSE---------------------------------------
## 
## slim_names <- hpk_rosters %>% dplyr::select(player_key, fullname) %>% unique()
## 
## player_stat_totals <- daily_player_stats %>%
##   dplyr::left_join(
##     slim_names, by = 'player_key'
##   ) %>%
##   dplyr::filter(!is.na(value)) %>%
##   dplyr::filter(!stat_id %in% c(58, 59)) %>%
##   dplyr::group_by(player_key, fullname, stat_id, stat_name) %>%
##   dplyr::summarize(
##     total_v = sum(as.numeric(value), na.rm = TRUE),
##     n = n()
##   )
## 
## unq_ids <- unique(daily_player_stats$stat_id) %>% sort()
## 
## for (i in unq_ids) {
## 
##   this_stat <- player_stat_totals %>%
##     dplyr::filter(stat_id == i) %>%
##     dplyr::arrange(desc(total_v))
## 
##   print(this_stat %>% head(5))
## 
## }
## 

## ----eval = FALSE--------------------------------------------------------
## daily_player_stats %>% dplyr::filter(player_key == '370.p.8849' & date == '2017-04-08') %>% arrange(stat_id) %>% print.AsIs()
## 
## archer_df <- daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8849') %>%
##   dplyr::group_by(player_key, stat_id, stat_name) %>%
##   dplyr::summarize(
##     total_v = sum(as.numeric(value), na.rm = TRUE)
##   )
## 
## lindor_df <- daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.9116') %>%
##   dplyr::group_by(player_key, stat_id, stat_name) %>%
##   dplyr::summarize(
##     total_v = sum(as.numeric(value), na.rm = TRUE)
##   )
## 
## eaton_df <- daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.9302') %>%
##   dplyr::group_by(player_key, stat_id, stat_name) %>%
##   dplyr::summarize(
##     total_v = sum(as.numeric(value), na.rm = TRUE)
##   )
## 
## belt_df <- daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8795') %>%
##   dplyr::group_by(player_key, stat_id, stat_name) %>%
##   dplyr::summarize(
##     total_v = sum(as.numeric(value), na.rm = TRUE)
##   )
## 
## 
## kershaw_df <- daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8180') %>%
##   dplyr::group_by(player_key, stat_id, stat_name) %>%
##   dplyr::summarize(
##     total_v = sum(as.numeric(value), na.rm = TRUE),
##     n = n()
##   )
## 
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8180' & stat_id == 42)
## 
## #is 8 H?
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.9116' & stat_id %in% c(3, 6, 8)) %>% print.AsIs()
## #yes, 8 is H
## 
## #is 10 BB?
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8795' & stat_id %in% c(4, 8, 10, 65)) %>% print.AsIs()
## #10 is not BB - whatever it is, it doesn't count towards OBP
## 
## #is 18 BB?
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8795' & stat_id %in% c(4, 8, 18, 65)) %>% print.AsIs()
## #18 is consistent with being BB
## 
## #is 21 BB?
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8795' & stat_id %in% c(4, 8, 21, 65)) %>% print.AsIs()
## #NO
## 
## ##brandon belt had two walks or hbp on 04-09
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8795' & date == '2017-04-09') %>% print.AsIs()
## #maybe 18, or 21?
## 
## ##logan forsythe is a HBP guy
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8921' & stat_id %in% c(4, 8, 18, 65)) %>% print.AsIs()
## 
## #logan forsythe on 04-03 - had 2 HBP?
## daily_player_stats %>%
##   dplyr::filter(player_key == '370.p.8921' & date == '2017-04-03') %>% print.AsIs()
## #could be 20, 52
## #prob 20
## 
## kershaw_df %>% print.AsIs()

