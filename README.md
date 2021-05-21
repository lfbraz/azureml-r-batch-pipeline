# Azure ML Batch Pipeline with change based trigger
In this tutorial, we show how to create an Azure ML Pipeline that will be started from a change-based trigger. As an example, we demonstrate a scenario in which new audio files (.mp3) are added to blob storage, triggering an ML pipeline for processing these files and output the result to a SQL Database. The full notebook can be found [here](./notebooks/create-azureml-batch-pipeline.ipynb)

## Requirements

* Install Azure ML SDK
```python 
pip install azureml-sdk 
```

## Get Azure ML Workspace
```python 
from azureml.core import Workspace
ws = Workspace.from_config()
print('Workspace name: ' + ws.name, 
      'Azure region: ' + ws.location, 
      'Subscription id: ' + ws.subscription_id, 
      'Resource group: ' + ws.resource_group, sep = '\n')
```

## Get Computer Cluster
In this example we will use an existing cluster, however you can create a new one using the [SDK](https://docs.microsoft.com/en-us/azure/machine-learning/how-to-create-attach-compute-cluster?tabs=python).
```python
from azureml.core.compute import ComputeTarget, AmlCompute
from azureml.core.compute_target import ComputeTargetException

cluster_name = "<your-cluster-name>"

try:
    compute_target = ComputeTarget(workspace=ws, name=cluster_name)
    print('Found existing compute target')
except ComputeTargetException:
    print('Compute target not found')
```

## Configure the environment
We will create an [environment](https://docs.microsoft.com/en-us/azure/machine-learning/concept-environments) using a [`Dockerfile`](Dockerfile). This environment contains an R base image as well as some dependencies required to run the following examples.

```python
from azureml.core import Environment

env = Environment.from_dockerfile(name='r_env', dockerfile='Dockerfile')
```

## Configure the Pipeline
Now with the dependencies we will configure an [Azure ML Batch Pipeline](https://docs.microsoft.com/en-us/azure/machine-learning/how-to-create-machine-learning-pipelines). For more details about how to create pipelines we encourage you to take a look in this [MS Learn module](https://docs.microsoft.com/en-us/learn/modules/create-pipelines-in-aml/).

### Set up input parameters
In this example we use [pipeline parameters](https://docs.microsoft.com/en-us/python/api/azureml-pipeline-core/azureml.pipeline.core.graph.pipelineparameter?view=azure-ml-py) to be able to submit experiment passing some default values (very useful to test the pipeline). We use two datasets, one for the mp3 file and another one to read an rds file from our Data Store (blob storage).

```python

# Get the Data Store
datastore = Datastore.get(workspace=ws, datastore_name="<your-datastore>")

# RDS Input Data parameter
input_rds_datapath = DataPath(datastore=datastore, path_on_datastore='r-pipeline-data/rds/accidents.Rd')
input_rds_data_pipeline_param = (PipelineParameter(name="input_rds_data", default_value=input_rds_datapath),
                             DataPathComputeBinding(mode='mount'))

# MP3 Input Data parameter
input_mp3_datapath = DataPath(datastore=datastore, path_on_datastore='r-pipeline-data/mp3')
input_mp3_data_pipeline_param = (PipelineParameter(name="input_mp3_data", default_value=input_mp3_datapath),
                             DataPathComputeBinding(mode='mount'))
```

### Set up an intermediate output
Now we set up an intermediate output. It can be used for example as input to the next steps. We also use the [Azure ML default storage](https://docs.microsoft.com/en-us/azure/machine-learning/concept-azure-machine-learning-architecture) to persist these data.
```python

from azureml.data import OutputFileDatasetConfig

datastore_output = ws.get_default_datastore()

output_data = OutputFileDatasetConfig(name="output_data", 
                                      destination=(datastore_output, "output_data/{run-id}/{output-name}")).as_upload()

```

### Create the steps
With the input and the intermediate output configured we can set up the pipelines' steps. We will have two steps: train and persist. The first one is a very simple [R script](R-model.R) receiving both input data (mp3 and rds) and producing an output (for the next step). The second one is a [Python script](Persist-Data.py) that receives (as input) the result from the first step and persists into a SQL Database.

```python

source_directory = '.'

train_config = ScriptRunConfig(source_directory=source_directory,
                            command=['Rscript R-model.R '
                                     '--input_rds_data', input_rds_data_pipeline_param,
                                     '--input_mp3_data', input_mp3_data_pipeline_param,
                                     '--output_data', output_data
                                    ],
                            compute_target=compute_target,
                            environment=env)

# R Model
train = CommandStep(name='train', 
                    runconfig=train_config, 
                    allow_reuse=False, 
                    inputs=[input_rds_data_pipeline_param, input_mp3_data_pipeline_param, output_data_pipeline_param],
                    outputs=[output_data]
                   )

# Persist data (python script)
run_config = RunConfiguration()
run_config.environment.python.conda_dependencies = CondaDependencies.create(conda_packages=['pandas', 'pyodbc'])

persist_data = PythonScriptStep(
       script_name="persist_data.py",
       arguments=["--raw_data", output_data.as_input('raw_data')],
       inputs=[output_data],
       compute_target=compute_target,
       source_directory=source_directory,
       runconfig=run_config
)
```

## Submit the pipeline
Finally we can submit the pipeline, passing the input parameters (for example sample audio).

```python
from azureml.pipeline.core import Pipeline
from azureml.core import Experiment

pipeline = Pipeline(workspace=ws, steps=[train, persist_data])

# Parameters to tests our pipeline
test_rds_path = DataPath(datastore=datastore, path_on_datastore='./rds/accidents.Rd')
test_mp3_path = DataPath(datastore=datastore, path_on_datastore='./mp3/file_example_MP3_5MG_01.mp3')

experiment_name = 'R-batch-scoring'
pipeline_run = Experiment(ws, experiment_name).submit(pipeline, 
                                                      pipeline_parameters={"input_rds_data": test_rds_path,
                                                                           "input_mp3_data": test_mp3_path 
                                                                          })
```

And check the execution log

```python
from azureml.widgets import RunDetails
RunDetails(pipeline_run).show()
```

![](/images/azureml-pipeline-execution-log.jpg)

## Publish the pipeline
After the test we can publish the pipeline, so it will be available to be triggered outside the Azure ML (for example from an Azure Data Factory Pipeline).

```python
published_pipeline = pipeline.publish(name='pipeline-batch-score',
                                      description='R batch pipeline')
```

## Create the change-based schedule
We can also [trigger our pipeline](https://docs.microsoft.com/en-us/azure/machine-learning/how-to-trigger-published-pipeline) recurrently or using a change-based schedule. In this case we can trigger the pipeline for example when a new mp3 file is added in a specific blob container.

```python
from azureml.data.datapath import DataPath

datastore = Datastore.get(ws, datastore_name='<your-datastore>')

reactive_schedule = Schedule.create(ws, 
                                    name="R-Schedule", 
                                    description="Based on input file change.",
                                    pipeline_id=published_pipeline.id, 
                                    experiment_name=experiment_name, 
                                    datastore=datastore,
                                    polling_interval=1,
                                    data_path_parameter_name="input_mp3_data",
                                    path_on_datastore='r-pipeline-data/mp3/' 
                                   )

```
## Set secrets to Key Vault
In this example we use [Azure Key Vault](https://azure.microsoft.com/pt-br/services/key-vault/) to protect some sensitive data (username, password, etc.). We can use the default Azure Key Vault integrated into the Azure ML Workspace for this task, so it will be easier to get the secrets during the Pipelines' execution. Please check [this doc](https://docs.microsoft.com/en-us/azure/machine-learning/how-to-use-secrets-in-runs) to obtain more details about this process.

```python
keyvault = ws.get_default_keyvault()

username = '<your-user-name>'
password = '<your-password>'
database = '<your-database>'
server = '<your-server>'

keyvault.set_secret(name="username", value = username)
keyvault.set_secret(name="password", value = username)
keyvault.set_secret(name="database", value = database)
keyvault.set_secret(name="server", value = server)
```
