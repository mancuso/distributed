dnf install java-11-openjdk
wget https://downloads.apache.org/kafka/2.6.0/kafka_2.12-2.6.0.tgz
tar zxvf kafka_2.12-2.6.0.tgz
mv kafka_2.12-2.6.0 /usr/local/kafka
vim /etc/systemd/system/zookeeper.service
vim /etc/systemd/system/kafka.service
