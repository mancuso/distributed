from time import sleep
from json import dumps
from kafka import KafkaProducer

TOPIC='microservice'

producer = KafkaProducer(bootstrap_servers=['localhost:9092'],
                         value_serializer=lambda x:
                         dumps(x).encode('utf-8'))

for e in range(1000):
    data = {'number' : e}
    producer.send(TOPIC, value=data)
    sleep(5)
