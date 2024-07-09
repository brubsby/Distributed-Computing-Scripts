#!/bin/bash

# Teal Dulcet
# wget -qO - https://raw.github.com/tdulcet/Distributed-Computing-Scripts/master/mprime2.sh | bash -s --
# ./mprime2.sh <Computer number> [PrimeNet User ID] [Computer name] [Type of work] [Idle time to run (mins)]
# ./mprime2.sh <N> "$USER" "$HOSTNAME" 150 10
# ./mprime2.sh <N> ANONYMOUS

DIR="mprime"
FILE32=p95v3019b20.linux32.tar.gz
SUM32=2b7e5d8447246cbb4fabebfd8599cee16a407e659b3bb5142314023e9f0d11e1
FILE64=p95v3019b20.linux64.tar.gz
SUM64=4ce2377e03deb4cf189523136e26401ba08f67857a128e420dd030d00cdca601
if [[ $# -lt 1 || $# -gt 5 ]]; then
	echo "Usage: $0 <Computer number> [PrimeNet User ID] [Computer name] [Type of work] [Idle time to run (mins)]" >&2
	exit 1
fi
N=$1
USERID=${2:-$USER}
COMPUTER=${3:-$HOSTNAME}
TYPE=${4:-150}
TIME=${5:-10}
RE='^[0-9]+$'
if ! [[ $N =~ $RE ]]; then
	echo "Usage: <Computer number> must be a number" >&2
	exit 1
fi
RE='^([024568]|1(0[0124]|5[012345]|6[01])?)$'
if ! [[ $TYPE =~ $RE ]]; then
	echo "Usage: [Type of work] is not a valid number" >&2
	exit 1
fi
RE='^([0-9]*\.)?[0-9]+$'
if ! [[ $TIME =~ $RE ]]; then
	echo "Usage: [Idle time to run] must be a number" >&2
	exit 1
fi
echo -e "PrimeNet User ID:\t$USERID"
echo -e "Computer name:\t\t$COMPUTER"
echo -e "Type of work:\t\t$TYPE"
echo -e "Idle time to run:\t$TIME minutes\n"
if [[ -e idletime.sh ]]; then
	bash -- idletime.sh
else
	wget -qO - https://raw.github.com/tdulcet/Distributed-Computing-Scripts/master/idletime.sh | bash -s
fi
if ! command -v expect >/dev/null; then
	echo -e "Installing Expect"
	echo -e "Please enter your password if prompted.\n"
	sudo apt-get update -y
	sudo apt-get install -y expect
fi
TIME=$(echo "$TIME" | awk '{ printf "%g", $1 * 60 }')

ARCHITECTURE=$(getconf LONG_BIT)
echo -e "\nArchitecture:\t\t\t$HOSTTYPE (${ARCHITECTURE}-bit)"

MEMINFO=$(</proc/meminfo)
TOTAL_PHYSICAL_MEM=$(echo "$MEMINFO" | awk '/^MemTotal:/ { print $2 }')
echo -e "Total memory (RAM):\t\t$(printf "%'d" $((TOTAL_PHYSICAL_MEM >> 10))) MiB ($(printf "%'d" $((((TOTAL_PHYSICAL_MEM << 10) / 1000) / 1000))) MB)\n"

if [[ -d $DIR && -x "$DIR/mprime" ]]; then
	echo -e "MPrime is already downloaded\n"
	cd "$DIR"
	DIR=$PWD
else
	if [[ $ARCHITECTURE -eq 32 ]]; then
		FILE=$FILE32
		SUM=$SUM32
	else
		FILE=$FILE64
		SUM=$SUM64
	fi
	if ! mkdir "$DIR"; then
		echo "Error: Failed to create directory $DIR" >&2
		exit 1
	fi
	cd "$DIR"
	DIR=$PWD
	echo -e "Downloading MPrime\n"
	wget https://www.mersenne.org/download/software/v30/30.19/$FILE
	if [[ "$(sha256sum $FILE | head -c 64)" != "$SUM" ]]; then
		echo "Error: sha256sum does not match" >&2
		echo "Please run \"rm -r ${DIR@Q}\" make sure you are using the latest version of this script and try running it again" >&2
		echo "If you still get this error, please create an issue: https://github.com/tdulcet/Distributed-Computing-Scripts/issues" >&2
		exit 1
	fi
	echo -e "\nDecompressing the files\n"
	tar -xzvf $FILE
fi
echo -e "\nOptimizing MPrime for your computer\nThis may take a while…\n"
./mprime -A"$N" -b
echo -e "\nSetting up MPrime\n"
if [[ -e ../mprime2.exp ]]; then
	cp ../mprime2.exp .
else
	wget -nv https://raw.github.com/tdulcet/Distributed-Computing-Scripts/master/mprime2.exp
fi
sed -i '/^expect {/a \\t"stage 2 memory in GiB (*):" { sleep 1; send -- "'"$(echo "$TOTAL_PHYSICAL_MEM" | awk '{ printf "%g", ($1 * 0.8) / 1024 / 1024 }')"'\\r"; exp_continue }' mprime2.exp
expect mprime2.exp -- "$USERID" "$COMPUTER" "$TYPE" "$N"
echo -e "\nStarting MPrime\n"
nohup ./mprime -A"$N" -d >>"mprime$N.out" &
#crontab -l | { cat; echo "@reboot cd ${DIR@Q} && nohup ./mprime -A$N -d >> 'mprime$N.out' &"; } | crontab -
cat <<EOF >mprime.sh
#!/bin/bash

# Copyright © 2020 Teal Dulcet
# Start MPrime if the computer has not been used in the specified idle time and stop it when someone uses the computer
# ${DIR@Q}/mprime.sh

if who -s | awk '{ print \$2 }' | (cd /dev && xargs -r stat -c '%U %X') | awk '{if ('"\${EPOCHSECONDS:-\$(date +%s)}"'-\$2<$TIME) { print \$1"\t"'"\${EPOCHSECONDS:-\$(date +%s)}"'-\$2; ++count }} END{if (count>0) { exit 1 }}' >/dev/null; then pgrep -x mprime >/dev/null || (cd ${DIR@Q} && exec nohup ./mprime -A$N -d >>'mprime$N.out' &) else pgrep -x mprime >/dev/null && killall mprime; fi
EOF
chmod +x mprime.sh
echo -e "\nRun this command for it to start if the computer has not been used in the specified idle time and stop it when someone uses the computer:\n"
echo "crontab -l | { cat; echo \"* * * * * ${DIR@Q}/mprime.sh\"; } | crontab -"
echo -e "\nTo edit the crontab, run \"crontab -e\""
