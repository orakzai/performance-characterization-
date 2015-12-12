
#!/bin/bash
#option is w = wordcount; t = terasort
option=$1

#option2 is which corruner to run m=mbw; s=stream.out; l=lbm; q=quantum; p=povray; o=omnet
option2=$2

#option3 is which framework s=spark f=flink
option3=$3 


tests=4
runsPerTest=3 #change parameter to increase the runs
totalTests=$tests*$runsPerTest
FLINK_DIR=~/flink
SPARK_DIR=~/spark/spark-1.5.2-bin-hadoop2.6

RESULTS_DIR=~/scripts/results
HADOOP_DIR=~/hadoop/bin/

if [ "$option3" == "f" ]
then
    FRAMEWORK="flink"   #flink, spark
else
    FRAMEWORK="spark"   #flink, spark
fi

APP_NAME="default" #wordcount, terasort
CORUNNER="default" #cmbw, cstream, clbm, clibquantum,cpov, comnet


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

#stop flink job manager  
#./build-target/bin/stop-local.sh
hdfsIp="hdfs://130.237.212.71:54310"
outputDir="/user/orak/${APP_NAME}/output"
inputDir="/user/orak/${APP_NAME}"
inputFile="$inputDir/input"
#inputFile="$inputDir/README.txt"

#empty the output directory
$HADOOP_DIR/hadoop fs -rm -r -f -skipTrash  $outputDir/*
#ssh orak@sky2.it.kth.se $HADOOP_DIR/hadoop fs rm -r $outputDir/*


#echo "Running Job Manager"
#	numactl --physcpubind=1 --membind=1 ./build-target/bin/start-local.sh
#	sleep 10

echo "Running Application on ${FRAMEWORK}"
for (( i=0; i<$totalTests; i++))
do
    if (($i%($tests) == 0))
    then
        #run normally no interference	
        echo "No interference"
        ./$CORUNNER
        ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER 
    elif (($i%($tests) == 1))
    then
        #interference on bw
        ./$CORUNNER b
        ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER b
    elif (($i%($tests) == 2))
    then
        #interference on cache
        ./$CORUNNER c
        ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER c
    elif (($i%($tests) == 3))
    then
        #interference on bw + cache
        ./$CORUNNER a
        ssh orak@sky2.it.kth.se 'bash -s'  < $CORUNNER a
    fi

    echo "...Instance $i..."
    start=$(date +%s.%N)

    if [ "$option3" == "f" ]                                                        
    then 
        if [ "$option" == "w" ];
        then 
            numactl --physcpubind=1 --membind=1 $FLINK_DIR/bin/flink run -q -p 2 -m 130.237.212.71:6123 $FLINK_DIR/examples/WordCount.jar $hdfsIp$inputFile  $hdfsIp$outputDir/$i
        elif [ "$option" == "t" ];
        then
            numactl --physcpubind=1 --membind=1 $FLINK_DIR/bin/flink run -q -p 2 -m 130.237.212.71:6123 -c eastcircle.terasort.FlinkTeraSort $FLINK_DIR/examples/terasort_2.10-0.0.1.jar $hdfsIp $inputFile $outputDir/$i 1 false false
         #numactl --physcpubind=1 --membind=1 $FLINK_DIR/bin/flink run -q -p 2 -m 130.237.212.71:6123 $FLINK_DIR/examples/PageRankBasic.jar $inputDir/nodes.txt $inputDir/links.txt $outputDir/$i 10000 10000
        fi	                                                                           
    else                                                                            
        if [ "$option" == "w" ];
        then
            numactl --physcpubind=1 --membind=1 $SPARK_DIR/bin/spark-submit --master spark://130.237.212.71:7077 --class WordCount ~/wordcount/target/wordcount-1.0.jar $hdfsIp$inputFile  $hdfsIp$outputDir/$i
        elif [ "$option" == "t" ];
        then
            numactl --physcpubind=1 --membind=1 $SPARK_DIR/bin/spark-submit --master spark://130.237.212.71:7077 --class com.github.ehiggs.spark.terasort.TeraSort $SPARK_DIR/spark-terasort/target/spark-terasort-1.0-SNAPSHOT-jar-with-dependencies.jar $hdfsIp$inputFile $hdfsIp$ouputDir/$i
        fi
    fi                                                                              
                   
    end=$(date +%s.%N)
    runtime[$i]=$(echo "$end - $start" | bc)

done

#STOP THE CORUNNERS
./$CORUNNER
ssh orak@sky2.it.kth.se 'bash -s' < $CORUNNER

#Print formatted times
avgNormal=0.0
avgBw=0.0
avgCache=0.0
avgCacheBw=0.0

for ((r=0; r<$totalTests; r++))
do
    interference="no"
     if (($r%$tests == 0))
    then
        #run normally no interference	
        interference="no"
        avgNormal=$(bc <<< "scale=6;$avgNormal + ${runtime[$r]}")
    elif (($r%$tests == 1))
    then
        #interference on bw
        interference="bw"
        avgBw=$(bc <<< "scale=6;$avgBw + ${runtime[$r]}")
    elif (($r%$tests == 2))
    then
        #interference on cache
        interference="cache"
        avgCache=$(bc <<< "scale=6;$avgCache + ${runtime[$r]}")
    elif (($r%$tests == 3))
    then
        #interference on bw + cache
        interference="bwcache"
        avgCacheBw=$(bc <<< "scale=6;$avgCacheBw + ${runtime[$r]}")
    fi

    printf "${FRAMEWORK},${APP_NAME},${CORUNNER},${interference},%.6f \n" ${runtime[$r]}   >> $RESULTS_CSV
  printf "${FRAMEWORK},${APP_NAME},${CORUNNER},${interference} \t\t - Execution time $r: %.6f seconds\n" ${runtime[$r]} >> $RESULTS_FILE
done

avgNormal=$(bc <<< "scale=6;$avgNormal/$runsPerTest")
avgBw=$(bc <<< "scale=6;$avgBw/$runsPerTest")
avgCache=$(bc <<< "scale=6;$avgCache/$runsPerTest")
avgCacheBw=$(bc <<< "scale=6;$avgCacheBw/$runsPerTest")

printf "==========================\n" >> $RESULTS_FILE
printf "Timestamp: [$(date)]\n" >> $RESULTS_FILE
printf "==========================\n" >> $RESULTS_FILE
printf "Average Execution Times ($APP_NAME) ($CORUNNER):\n" >> $RESULTS_FILE
printf "Normal:\t %.2f seconds\n" $avgNormal >> $RESULTS_FILE
printf "BW:\t %.2f seconds\n" $avgBw >> $RESULTS_FILE
printf "Cache:\t %.2f seconds\n" $avgCache >> $RESULTS_FILE
printf "CacheBW:\t%.2f seconds\n" $avgCacheBw  >> $RESULTS_FILE
printf "==========================\n" >> $RESULTS_FILE

printf "Average Degradation ($APP_NAME) ($CORUNNER):\n" >> $RESULTS_FILE
printf "Normal:\t %.2f %%\n"  $(bc <<< "scale=6;($avgNormal-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "BW:\t %.0f %%\n" $(bc <<< "scale=6;($avgBw-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "Cache:\t %.2f %%\n" $(bc <<< "scale=6;($avgCache-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "CacheBW:\t%.2f %%\n" $(bc <<< "scale=6;($avgCacheBw-$avgNormal)*100/$avgNormal") >> $RESULTS_FILE
printf "==========================\n" >> $RESULTS_FILE



