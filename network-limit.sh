#!/bin/bash

# Check if a parameter is provided
if [ -z "$1" ]; then
  echo "Please specify a container instance"
  exit 1
fi

INSTANCE_NAME=$1

# Check if the Docker instance exists
if ! docker ps --format '{{.Names}}' | grep -wq "$INSTANCE_NAME"; then
  echo "Error: The specified container instance '$INSTANCE_NAME' does not exist or is not running"
  exit 1
fi

# Get the container's network interface
CONTAINER_ID=$(docker ps -q -f name=$INSTANCE_NAME)
INTERFACE=$(docker exec $CONTAINER_ID /bin/sh -c "cat /sys/class/net/eth0/iflink | xargs -I {} basename /sys/devices/virtual/net/{}/uevent")
echo "###: ${INTERFACE}"
INTERFACE=br-$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' "${INSTANCE_NAME}" | cut -c1-12)
echo "###2: ${INTERFACE}"
# Check if the interface was successfully retrieved
if [ -z "$INTERFACE" ]; then
  echo "Error: Unable to get the container's network interface"
  exit 1
fi

# Apply the speed limit to the instance
echo "Applying speed limit to container instance '$INSTANCE_NAME'..."



# Remove previous tc rules
tc qdisc del dev $INTERFACE root 2>/dev/null

# Add root queueing discipline
tc qdisc add dev $INTERFACE root handle 1: htb default 50

# Add main class
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 50mbit ceil 60mbit

# Add subclass for regular speed limit
tc class add dev $INTERFACE parent 1:1 classid 1:50 htb rate 50mbit ceil 50mbit

# Add subclass for temporary speed allowance
tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate 60mbit ceil 60mbit burst 15k

# Set filter rules
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:50

# Temporary speed boost for 50 seconds
tc qdisc add dev $INTERFACE parent 1:20 handle 20: netem rate 60mbit limit 15000

echo "Speed limit rules applied. Container instance '$INSTANCE_NAME' has a regular speed limit of 50Mbps, with a temporary allowance of 60Mbps for 30 seconds."

# Wait for 30 seconds then revert to regular speed limit
sleep 30

# Remove the temporary speed boost class
tc qdisc del dev $INTERFACE parent 1:20 handle 20: netem

echo "Reverted to regular speed limit of 30Mbps."

