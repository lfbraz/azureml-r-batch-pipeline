# code in data_prep.py
from azureml.core import Run
import argparse
import os
import pandas as pd
import pyodbc

# Get the experiment run context
run = Run.get_context()

# Get arguments
parser = argparse.ArgumentParser()
parser.add_argument('--raw_data', type=str)
args = parser.parse_args()
input_data = args.raw_data

df = pd.read_csv(input_data + '/audio.csv', delimiter=",")

# Set connection (get secrets from Key Vault)
username = run.get_secret(name="username")
password = run.get_secret(name="password")
database = run.get_secret(name="database")
server = run.get_secret(name="server")
driver = '{ODBC Driver 17 for SQL Server}'

# Persist data
cnxn = pyodbc.connect('DRIVER=' + driver + ';SERVER=' + server + ';DATABASE=' + database + ';UID=' + username + ';PWD=' + password)
cursor = cnxn.cursor()
cursor.execute("INSERT INTO TB_MODEL_RESULT (RESULT) values(?)", int(df['length(audio_file@left)'][0]))
cnxn.commit()
cursor.close()

print('Data persisted')
