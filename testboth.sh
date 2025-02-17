#!/bin/bash

#option is w = wordcount; t = terasort
option=$1

#option2 is which corruner to run m=mbw; s=stream.out; l=lbm; q=quantum; p=povray; o=omnet
option2=$2

#option3 is which framework s=spark f=flink
option3=$3 


tests=2
runsPerTest=1 #change parameter to increase the runs
totalTests=$tests*$runsPerTest
FLINK_DIR=~/flink
SPARK_DIR=~/spark/spark-1.5.2-bin-hadoop2.6

LOG_FILE=~/scripts/logs/log
LOG_FILE_FRAMEWORK=~/scripts/logs
RESULTS_DIR=~/scripts/results
HADOOP_DIR=~/hadoop/bin/
START_FRAMEWORK=''
STOP_FRAMEWORK=''

if [ "$option3" == "f" ]
then
    FRAMEWORK="flink"   #flink
    START_FRAMEWORK='startflink.sh'
    STOP_FRAMEWORK='stopflink.sh'
else
    FRAMEWORK="spark"   #, spark
    START_FRAMEWORK='startspark.sh'
    STOP_FRAMEWORK='stopspark.sh'
fi

APP_NAME="default" #wordcount, terasort
CORUNNER="default" #cmbw, cstream, clbm, clibquantum,cpov, comnet
LOG_FILE_FRAMEWORK=$LOG_FILE_FRAMEWORK/$FRAMEWORK

if [ "$option" == "w" ];    
then 
    APP_NAME="wordcount"
elif [ "$option" == "t" ];
then
    APP_NAME="terasort"
fi	

if [ "$option2" == "m" ];    
then 
    CORUNNER="cmbw"
elif [ "$option2" == "s" ];
then
    CORUNNER="cstream"
elif [ "$option2" == "l" ];
then
    CORUNNER="clbm"
elif [ "$option2" == "q" ];
then
    CORUNNER="clibquantum"
elif [ "$option2" == "p" ];
then
    CORUNNER="cpov"
elif [ "$option2" == "o" ];
then
    CORUNNER="comnet"
fi	


RESULTS_FILE="${RESULTS_DIR}/${FRAMEWORK}_${APP_NAME}.txt"
RESULTS_CSV="${RESULTS_DIR}/results.csv"

CORUNNER="${CORUNNER}.sh"

declare -A runtime
declare -A runtimeSuccess

#stop flink job manager  
#./build-target/bin/stop-local.sh
hdfsIp="hdfs://130.237.212.71:54310"
outputDir="/user/orak/${APP_NAME}/output"
inputDir="/user/orak/${APP_NAME}"
inputFile="$inputDir/input1"
#inputFile="$inputDir/README.txt"

echo "=======================================" >> $LOG_FILE
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - ${FRAMEWORK} | ${CORUNNER} | ${APP_NAME} |" >> $LOG_FILE

#empty the output directory
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Empty output directory..." >> $LOG_FILE
$HADOOP_DIR/hadoop fs -rm -r -f -skipTrash  $outputDir/*


for (( i=0; i<$totalTests; i++))
do
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting ${FRAMEWORK}" >> $LOG_FILE
    ./$START_FRAMEWORK >> $LOG_FILE_FRAMEWORK 2>&1
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Started ${FRAMEWORK}" >> $LOG_FILE
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting ${CORUNNER}" >> $LOG_FILE

    interference='no'

    if (($i%($tests) == 0))
    then
        #run normally no interference	
        echo "No interference"
        ./$CORUNNER  
       # ./$CORUNNER a

        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting ${CORUNNER} on remote (no interference)" >> $LOG_FILE
        #ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER 
        ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup ./$CORUNNER  > foo.out 2>foo.err < /dev/null &'"
        interference='no'
    elif (($i%($tests) == 1))
    then
        #interference on bw
        ./$CORUNNER b
       # ./$CORUNNER c

        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting ${CORUNNER} on remote (bw)" >> $LOG_FILE
        #ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER b
        ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup ./$CORUNNER b > foo.out 2>foo.err < /dev/null &'"
        interference='bw'
    elif (($i%($tests) == 2))
    then
        #interference on cache
        ./$CORUNNER c

        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting ${CORUNNER} on remote (cache)" >> $LOG_FILE
        #ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER c
        ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup ./$CORUNNER c > foo.out 2>foo.err < /dev/null &'"
        interference='cache'
    elif (($i%($tests) == 3))
    then
        #interference on bw + cache
        ./$CORUNNER a

        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting ${CORUNNER} on remote (bwcache)" >> $LOG_FILE
        #ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER a
        ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup ./$CORUNNER a > foo.out 2>foo.err < /dev/null &'"
        interference='bwcache'
    fi
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Started ${CORUNNER}. Waiting for 60 seconds..." >> $LOG_FILE

    sleep 60 # wait here for framework and corrunners to properly start

    #start measuring performance counters here - they wait for 5 secs
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting performance counters..." >> $LOG_FILE
    sudo ./measureCounters.sh "$RESULTS_DIR/counters/${FRAMEWORK}_${APP_NAME}_${CORUNNER}_$i/" &
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Starting performance counters on remote..." >> $LOG_FILE
    #ssh orak@sky2.it.kth.se sudo ~/scripts/measureCounters.sh "$RESULTS_DIR/counters/${FRAMEWORK}_${APP_NAME}_${CORUNNER}_$i/" &
    ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup sudo ./measureCounters.sh $RESULTS_DIR/counters/${FRAMEWORK}_${APP_NAME}_${CORUNNER}_$i/ > foo.out 2>foo.err < /dev/null &'"

    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Started performance counters" >> $LOG_FILE
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - ...Instance $i..." >> $LOG_FILE

    start=$(date +%s.%N)
    #start=$(date +%Y-%m-%d\ %H:%M:%S +%s.%N)
    if [ "$option3" == "f" ]                                                        
    then 
        if [ "$option" == "w" ];
        then 
            numactl --physcpubind=1 --membind=1 $FLINK_DIR/bin/flink run -p 2 -m 130.237.212.71:6123 $FLINK_DIR/examples/WordCount.jar $hdfsIp$inputFile  $hdfsIp$outputDir/$i >> $LOG_FILE_FRAMEWORK 2>&1
        elif [ "$option" == "t" ];
        then
            numactl --physcpubind=1 --membind=1 $FLINK_DIR/bin/flink run -p 2 -m 130.237.212.71:6123 -c eastcircle.terasort.FlinkTeraSort $FLINK_DIR/examples/terasort_2.10-0.0.1.jar $hdfsIp $inputFile $outputDir/$i 1 false false >> $LOG_FILE_FRAMEWORK 2>&1
            #numactl --physcpubind=1 --membind=1 $FLINK_DIR/bin/flink run -q -p 2 -m 130.237.212.71:6123 $FLINK_DIR/examples/PageRankBasic.jar $inputDir/nodes.txt $inputDir/links.txt $outputDir/$i 10000 10000
        fi	                                                                           
    else                                                                            
        if [ "$option" == "w" ];
        then
            numactl --physcpubind=1 --membind=1 $SPARK_DIR/bin/spark-submit --master spark://130.237.212.71:7077 --class WordCount ~/wordcount/target/wordcount-1.0.jar $hdfsIp$inputFile  $hdfsIp$outputDir/$i >> $LOG_FILE_FRAMEWORK 2>&1
        elif [ "$option" == "t" ];
        then
            numactl --physcpubind=1 --membind=1 $SPARK_DIR/bin/spark-submit --master spark://130.237.212.71:7077 --class com.github.ehiggs.spark.terasort.TeraSort $SPARK_DIR/spark-terasort/target/spark-terasort-1.0-SNAPSHOT-jar-with-dependencies.jar $hdfsIp$inputFile $hdfsIp$ouputDir/$i >> $LOG_FILE_FRAMEWORK 2>&1
        fi
    fi                                                                              

    # check if application executed successfully
    if [ "$?" = "0" ];
    then                                                         
        runtimeSuccess[$i]='success'
        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - SUCCESS $i" >> $LOG_FILE
    else                                                                        
        echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - FAILED $i" >> $LOG_FILE
        runtimeSuccess[$i]='fail'
    fi

    end=$(date +%s.%N)
    #end=$(date +%Y-%m-%d\ %H:%M:%S +%s.%N)
    runtime[$i]=$(echo "$end - $start" | bc)

    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Finished  in ${runtime[$i]} seconds" >> $LOG_FILE

    printf "$(date +%Y-%m-%d\ %H:%M:%S),${FRAMEWORK},${APP_NAME},${CORUNNER},${interference},${runtimeSuccess[$i]},%.6f \n" ${runtime[$i]}   >> $RESULTS_CSV

    #stop the measure counters process on both sky1 & 2
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Stoping performance counters" >> $LOG_FILE
    sudo ./stopMeasureCounters.sh
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Stoping performance counters on remote" >> $LOG_FILE
    ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup sudo ./stopMeasureCounters.sh > foo.out 2>foo.err < /dev/null &'"

    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Stoping ${FRAMEWORK}" >> $LOG_FILE
    ./$STOP_FRAMEWORK >> $LOG_FILE_FRAMEWORK 2>&1

    #plot the measure counters process on both sky1 & 2
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Plotting performance counters" >> $LOG_FILE
    sudo ./plotMeasureCounters.sh $RESULTS_DIR/counters/${FRAMEWORK}_${APP_NAME}_${CORUNNER}_$i/
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Plotting performance counters on remote" >> $LOG_FILE
    ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup sudo ./plotMeasureCounters.sh $RESULTS_DIR/counters/${FRAMEWORK}_${APP_NAME}_${CORUNNER}_$i/ > foo.out 2>foo.err < /dev/null &'"


    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Wait 50 seconds for ${FRAMEWORK} to stop... " >> $LOG_FILE
    sleep 50 #wait for framework to stop
    ps -ef | grep ${FRAMEWORK} | grep -v grep | awk '{print $2}' | xargs kill -9 
    ssh -n -f orak@sky2.it.kth.se "ps -ef | grep ${FRAMEWORK} | grep -v grep | awk '{print $2}' | xargs kill -9 > foo.out 2>foo.err < /dev/null &'"
done

#STOP THE CORUNNERS
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Stoping ${CORUNNER}... " >> $LOG_FILE
./$CORUNNER
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] - Stoping ${CORUNNER} on remote... " >> $LOG_FILE
#ssh orak@sky2.it.kth.se 'bash -s' < $CORUNNER
ssh -n -f orak@sky2.it.kth.se "sh -c 'cd /home/orak/scripts/; nohup ./$CORUNNER  > foo.out 2>foo.err < /dev/null &'"

#Print formatted times
avgNormal=0.0
avgBw=0.0
avgCache=0.0
avgBwCache=0.0

successNormal=0
successBw=0
successCache=0
successBwCache=0

for ((r=0; r<$totalTests; r++))
do
    interference="no"
    if (( $r%$tests == 0 )) && (( "${runtimeSuccess[$r]}" == 'success' ));
    then
        #run normally no interference	
        interference="no"
        avgNormal=$(bc <<< "scale=6;$avgNormal + ${runtime[$r]}")
        successNormal=$((successNormal + 1))
    elif (( $r%$tests == 1 )) && (( "${runtimeSuccess[$r]}" == 'success' ));
    then
        #interference on bw
        interference="bw"
        avgBw=$(bc <<< "scale=6;$avgBw + ${runtime[$r]}")
        successBw=$((successBw + 1))
    elif (( $r%$tests == 2 )) && (( "${runtimeSuccess[$r]}" == 'success' ));
    then
        #interference on cache
        interference="cache"
        avgCache=$(bc <<< "scale=6;$avgCache + ${runtime[$r]}")
        successCache=$((successCache + 1))
    elif (( $r%$tests == 3 )) && (( "${runtimeSuccess[$r]}" == 'success' ));
    then
        #interference on bw + cache
        interference="bwcache"
        avgBwCache=$(bc <<< "scalej;=6;$avgBwCache + ${runtime[$r]}")
        successBwCache=$((successBwCache + 1))
    fi

    printf "${FRAMEWORK},${APP_NAME},${CORUNNER},${interference},${runtimeSuccess[$r]},%.6f \n" ${runtime[$r]}   >> ${RESULTS_CSV}.bkp
    printf "${FRAMEWORK},${APP_NAME},${CORUNNER},${interference},${runtimeSuccess[$r]}\t\t\t - Execution time $r: %.6f seconds\n" ${runtime[$r]} >> $RESULTS_FILE
done

avgNormal=$(bc <<< "scale=6;$avgNormal/$successNormal")
avgBw=$(bc <<< "scale=6;$avgBw/$successBw")
avgCache=$(bc <<< "scale=6;$avgCache/$successCache")
avgBwCache=$(bc <<< "scale=6;$avgBwCache/$successBwCache")

printf "==========================\n" >> $RESULTS_FILE
printf "Timestamp: [$(date +%Y-%m-%d\ %H:%M:%S)]\n" >> $RESULTS_FILE
printf "==========================\n" >> $RESULTS_FILE
printf "Average Execution Times ($APP_NAME) ($CORUNNER):\n" >> $RESULTS_FILE
printf "Normal:\t %.2f seconds\n" $avgNormal >> $RESULTS_FILE
printf "BW:\t %.2f seconds\n" $avgBw >> $RESULTS_FILE
printf "Cache:\t %.2f seconds\n" $avgCache >> $RESULTS_FILE
printf "CacheBW:\t%.2f seconds\n" $avgBwCache  >> $RESULTS_FILE
printf "==========================\n" >> $RESULTS_FILE

printf "Average Degradation ($APP_NAME) ($CORUNNER):\n" >> $RESULTS_FILE
printf "Normal:\t %.2f %%\n"  $(bc <<< "scale=6;($avgNormal-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "BW:\t %.0f %%\n" $(bc <<< "scale=6;($avgBw-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "Cache:\t %.2f %%\n" $(bc <<< "scale=6;($avgCache-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "CacheBW:\t%.2f %%\n" $(bc <<< "scale=6;($avgBwCache-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "==========================\n" >> $RESULTS_FILE



