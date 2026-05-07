# !/bin/bash
echo "test_pattern="$1 

CONFIG_FILE=/home/ajno5/work/2_pattern/dgemm/config/whisper_rv64gcv_config.json
echo "configuration file="$CONFIG_FILE

OPTION=" --counters --semihosting " 


if [[ "$2" == "gdb" ]]; then
    echo "Running with debugger."
    gdb-multiarch $1 --ex "target remote | whisper --configfile "$CONFIG_FILE $OPTION "--gdb "$1
else
    echo "Running normally with: $1"
    #whisper --configfile $CONFIG_FILE --logfile run_log.txt $1
    whisper --configfile $CONFIG_FILE $OPTION $1
fi
