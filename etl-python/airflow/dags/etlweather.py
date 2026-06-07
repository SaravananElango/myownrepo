from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.http.hooks.http import HttpHook
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.decorators import task
import pendulum
import requests
import json


start_date=  pendulum.datetime(2026, 1, 1, tz="UTC")
LATITUDE = '40.7128'
LONGITUDE = '-74.0060'
POSTGRES_CONN_ID = 'postgres_default'
API_CONN_ID = 'openweathermap_api'


default_args = {
    'owner': 'airflow',
    'start_date': start_date
}

##DAG

with DAG(dag_id='weather_etl_pipeline',
         default_args = default_args,
         schedule='@daily',
         catchup=False) as dags:
    @task
    def extract_weather_data():
     ## Extract weather data from OpenWeatherMap API using Airflow's HttpHook
     ##user HttpHook to make API request from airflow connection
        http_hook = HttpHook(method='GET', http_conn_id=API_CONN_ID)
     ## build api endpoint with latitude and longitude
     ## https://api.open-meteo.com/v1/forecast?latitude=40.7128&longitude=-74.0060&current_weather=true
        endpoint = f'/v1/forecast?latitude={LATITUDE}&longitude={LONGITUDE}&current_weather=true'
  

        ## make API request and get response

        response = http_hook.run(endpoint)

        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"API request failed with status code {response.status_code}")


     

    @task
    def transform_weather_data(weather_data):
        ## transorm current weather data to extract relevant fields
        current_weather = weather_data['current_weather']
        transformed_data = {
            'latitude': weather_data['latitude'],
            'longitude': weather_data['longitude'],
            'temperature': current_weather['temperature'],
            'windspeed': current_weather['windspeed'],
            'winddirection': current_weather['winddirection'],
            'weathercode': current_weather['weathercode'],
            'time': current_weather['time']
        }

        return transformed_data


    @task
    def load_weather_data(transformed_data):
        ## load transformed data into Postgres database
        pg_hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
        conn = pg_hook.get_conn()
        cursor = conn.cursor()
      
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS weather_data (
                latitude FLOAT,
                longitude FLOAT,
                temperature FLOAT,
                windspeed FLOAT,
                winddirection FLOAT,
                weathercode INT,
                time TIMESTAMP default current_timestamp
                       ); """)
        cursor.execute("""
            INSERT INTO weather_data (latitude, longitude, temperature, windspeed, winddirection, weathercode, time)
            VALUES (%s, %s, %s, %s, %s, %s, %s);
        """, (
            transformed_data['latitude'],
            transformed_data['longitude'],
            transformed_data['temperature'],
            transformed_data['windspeed'],
            transformed_data['winddirection'],
            transformed_data['weathercode'],
            transformed_data['time']
        ))
        conn.commit()
        cursor.close()
        conn.close()


        ## DAG workflow 

    weather_data = extract_weather_data()
    transformed_data = transform_weather_data(weather_data)
    load_weather_data(transformed_data)