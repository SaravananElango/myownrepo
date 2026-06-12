from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import time
import socket

default_args = {
    'owner': 'airflow',
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}


def get_worker_info(task_name, sleep_time):
    hostname = socket.gethostname()
    print(
        f"Starting {task_name} on worker: {hostname} started on : {datetime.now()}")
    time.sleep(sleep_time)
    print(
        f"Finished {task_name} on worker: {hostname} finished on : {datetime.now()}")
    return hostname


def collect_results(**context):
    print("Collecting results from parallel tasks")
    for i in range(1, 5):
        worker = context['ti'].xcom_pull(task_ids=f'task_{i}')
        print(f"Result from task_{i} : {worker}")


with DAG(
    dag_id='phase2_celery_demo',
    default_args=default_args,
    description='understanding celery executor with parallel tasks',
    schedule=None,  # manual trigger
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['phase2', 'learning', 'celery-executor'],
    max_active_tasks=5,
) as dag:

    # start task
    start = BashOperator(
        task_id='start',
        bash_command='echo "Starting the DAG execution"'
    )

    parallel_tasks = []
    for i in range(1, 5):
        task = PythonOperator(
            task_id=f'task_{i}',
            python_callable=get_worker_info,
            op_kwargs={'task_name': f'Task {i}', 'sleep_time': i * 2}
        )
        parallel_tasks.append(task)

    collect = PythonOperator(
        task_id='collect_results',
        python_callable=collect_results
    )

    end = BashOperator(
        task_id='end',
        bash_command='echo "DAG execution completed"'
    )

    # DAG Structure:
    #          start
    #        /   |   \   \
    #       A    B    C   D  ← runs in parallel
    #        \   |   /   /
    #         collect_results
    #              |
    #             end
    start >> parallel_tasks >> collect >> end
