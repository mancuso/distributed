#!/bin/bash
echo "Creating Consul Server"
docker run \
    -d \
    -p 8500:8500 \
    -p 8600:8600/udp \
    --name=sun \
    consul agent -server -ui -node=server-1 -bootstrap-expect=1 -client=0.0.0.0

echo "Creating Consul Client"
docker run \
    -d  \
    --name=earth \
    consul agent -node=client-1 -join=172.17.0.2

echo "Creating Counting Service"
docker run \
   -p 9001:9001 \
   -d \
   --name=moon \
   hashicorp/counting-service:0.0.2

echo "Updating Consul Client Configuration with New Service"
docker exec earth /bin/sh -c "echo '{\"service\": {\"name\": \"counting\", \"tags\": [\"go\"], \"port\": 9001}}' >> /consul/config/counting.json"

echo "Reloading Consult Client Configuration"
docker exec earth consul reload
