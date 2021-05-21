#' Copyright(c) Microsoft Corporation.
#' Licensed under the MIT license.

library(optparse)
library(tuneR)

options <- list(
  make_option(c("-r", "--input_rds_data")),
  make_option(c("-i", "--input_mp3_data")),
  make_option(c("-o", "--output_data"))    
)

opt_parser <- OptionParser(option_list = options)
opt <- parse_args(opt_parser)

accidents <- readRDS(file.path(opt$input_rds_data))
summary(accidents)

print(opt$input_mp3_data)
audio_file <- tuneR::readMP3(opt$input_mp3_data)

summary(audio_file)
audio_df <- as.data.frame(length(audio_file@left))
print("output_folder")
print(opt$output_data)
write.csv(x=audio_df, file=paste(opt$output_data,"/audio.csv", sep=""))
