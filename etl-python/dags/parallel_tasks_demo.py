from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import time

default_args = {
    'owner': 'airflow',
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}


def task_function(task_name, sleep_time):
    print(f"Starting {task_name}")
    time.sleep(sleep_time)
    print(f"Finished {task_name}")
    return f"{task_name} completed"


with DAG(
    dag_id='parallel_tasks_demo',
    default_args=default_args,
    description='understanding local executor with parallel tasks',
    schedule=None,  # manual trigger
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['phase1', 'learning', 'local-executor'],

) as dag:

    # start task
    start = BashOperator(
        task_id='start',
        bash_command='echo "Starting the DAG execution"'
    )

    task_A = PythonOperator(
        task_id='task_A',
        python_callable=task_function,
        op_kwargs={'task_name': 'Extract Data', 'sleep_time': 5}
    )

    task_B = PythonOperator(
        task_id='task_B',
        python_callable=task_function,
        op_kwargs={'task_name': 'Fetch API', 'sleep_time': 3}
    )

    task_C = PythonOperator(
        task_id='task_C',
        python_callable=task_function,
        op_kwargs={'task_name': 'Process Data', 'sleep_time': 4}
    )

    # Runs after all parallel tasks are done
    transform = PythonOperator(
        task_id='transform',
        python_callable=task_function,
        op_kwargs={'task_name': 'Transform Data', 'sleep_time': 2},
    )
    end = BashOperator(
        task_id='end',
        bash_command='echo "DAG execution completed"'
    )

    # DAG Structure:
    #          start
    #        /   |   \
    #       A    B    C   ← runs in parallel
    #        \   |   /
    #        transform
    #            |
    #           end

start >> [task_A, task_B, task_C] >> transform >> end
