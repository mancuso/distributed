#!/bin/bash
echo "Pull Consul  Docker Image"
docker pull consul
echo "Starting Consul Server"
docker run \
    -d \
    -p 8500:8500 \
    -p 8600:8600/udp \
    --name=sun \
    consul agent -server -ui -node=server-1 -bootstrap-expect=1 -client=0.0.0.0

echo "Starting Consul  Client"
docker run \
    -d
    --name=earth \
    consul agent -node=client-1 -join=172.17.0.2

echo "Pull Service"
docker pull hashicorp/counting-service:0.0.2
echo "Registering Service"

docker run \
   -p 9001:9001 \
   -d \
   --name=moon \
   hashicorp/counting-service:0.0.2
docker exec earth /bin/sh -c "echo '{\"service\": {\"name\": \"counting\", \"tags\": [\"go\"], \"port\": 9001}}' >> /consul/config/counting.json"

echo "Reload Consol Config"
docker exec earth consul reload
