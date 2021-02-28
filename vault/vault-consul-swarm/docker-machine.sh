#!/bin/bash

for i in 1 2 3; do
  docker-machine create node-$i;
done

#TOKEN=`docker-machine ssh node-1 -- docker swarm init --advertise-addr $(docker-machine ip node-1)`

#for i in 2 3; do
#    docker-machine ssh node-$i $TOKEN
#done

# list containers in swarm
# docker node ps $(docker node ls -q)

