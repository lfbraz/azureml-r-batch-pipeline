FROM rocker/tidyverse:4.0.0-ubuntu18.04

# SQL Database Client repos
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list > /etc/apt/sources.list.d/mssql-release.list

# Install python
RUN apt-get update -qq && \
 apt-get install -y python3

# SQL Database Client
RUN ACCEPT_EULA=Y apt-get install -y msodbcsql17

# Create link for python
RUN ln -f /usr/bin/python3 /usr/bin/python

# Install additional R packages
RUN R -e "install.packages(c('optparse', 'tuneR'), repos = 'https://cloud.r-project.org/')"
