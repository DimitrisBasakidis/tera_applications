#!/usr/bin/env bash

###################################################
#
# file: build.sh
#
# @Author:   Iacovos G. Kolokasis
# @Version:  21-09-2022 
# @email:    kolokasis@ics.forth.gr
#
# Compile Spark and Sparkbench suite
#
###################################################

. ./config.sh
# Check if the last command executed succesfully
#
# if executed succesfully, print SUCCEED
# if executed with failures, print FAIL and exit
check () {
    if [ "$1" -ne 0 ]
    then
        echo -e "  $2 \e[40G [\e[31;1mFAIL\e[0m]"
        exit
    else
        echo -e "  $2 \e[40G [\e[32;1mSUCCED\e[0m]"
    fi
}

#touch cg_exec scripts that create global variables
create_cgexec () {

    if [ -e "${TERA_APPS_REPO}/spark/scripts/run_cgexec.sh" ]; then
      rm "${TERA_APPS_REPO}/spark/scripts/run_cgexec.sh"
    fi

    if [ -e "${TERA_APPS_REPO}/spark/spark-3.3.0/bin/run_cgexec.sh" ]; then
      rm "${TERA_APPS_REPO}/spark/spark-3.3.0/bin/run_cgexec.sh"
    fi

    touch "${TERA_APPS_REPO}/spark/scripts/run_cgexec.sh"
    touch "${TERA_APPS_REPO}/spark/spark-3.3.0/bin/run_cgexec.sh"

    echo  -n "#!/usr/bin/env bash
    export LIBRARY_PATH=${TERAHEAP_REPO}/allocator/lib:\$LIBRARY_PATH
    export LD_LIBRARY_PATH=${TERAHEAP_REPO}/allocator/lib/:\$LD_LIBRARY_PATH
    export PATH=${TERAHEAP_REPO}/allocator/include/:\$PATH
    export C_INCLUDE_PATH=${TERAHEAP_REPO}/allocator/include/:\$C_INCLUDE_PATH
    export CPLUS_INCLUDE_PATH=${TERAHEAP_REPO}/allocator/include/:\$CPLUS_INCLUDE_PATH

    export LIBRARY_PATH=${TERAHEAP_REPO}/tera_malloc/lib:\$LIBRARY_PATH
    export LD_LIBRARY_PATH=${TERAHEAP_REPO}/tera_malloc/lib/:\$LD_LIBRARY_PATH
    export PATH=${TERAHEAP_REPO}/tera_malloc/include/:\$PATH
    export C_INCLUDE_PATH=${TERAHEAP_REPO}/tera_malloc/include/:\$C_INCLUDE_PATH
    export CPLUS_INCLUDE_PATH=${TERAHEAP_REPO}/tera_malloc/include/:\$CPLUS_INCLUDE_PATH
    \"\$@\"" >> "${TERA_APPS_REPO}/spark/scripts/run_cgexec.sh"


    echo  -n "#!/usr/bin/env bash
    export LIBRARY_PATH=${TERAHEAP_REPO}/allocator/lib:\$LIBRARY_PATH
    export LD_LIBRARY_PATH=${TERAHEAP_REPO}/allocator/lib/:\$LD_LIBRARY_PATH
    export PATH=${TERAHEAP_REPO}/allocator/include/:\$PATH
    export C_INCLUDE_PATH=${TERAHEAP_REPO}/allocator/include/:\$C_INCLUDE_PATH
    export CPLUS_INCLUDE_PATH=${TERAHEAP_REPO}/allocator/include/:\$CPLUS_INCLUDE_PATH

    export LIBRARY_PATH=${TERAHEAP_REPO}/tera_malloc/lib:\$LIBRARY_PATH
    export LD_LIBRARY_PATH=${TERAHEAP_REPO}/tera_malloc/lib/:\$LD_LIBRARY_PATH
    export PATH=${TERAHEAP_REPO}/tera_malloc/include/:\$PATH
    export C_INCLUDE_PATH=${TERAHEAP_REPO}/tera_malloc/include/:\$C_INCLUDE_PATH
    export CPLUS_INCLUDE_PATH=${TERAHEAP_REPO}/tera_malloc/include/:\$CPLUS_INCLUDE_PATH
    \"\$@\"" >> "${TERA_APPS_REPO}/spark/${SPARK_VERSION}/bin/run_cgexec.sh"

    chmod u+x "${TERA_APPS_REPO}/spark/scripts/run_cgexec.sh"
    chmod u+x "${TERA_APPS_REPO}/spark/${SPARK_VERSION}/bin/run_cgexec.sh"
}

# Print error/usage script message
usage() {
    echo
    echo "Usage:"
    echo -n "      $0 [option ...] [-h]"
    echo
    echo "Options:"
    echo "      -a  Compile and build both Spark and SparkBench Suite" 
    echo "      -s  Compile and build only Spark" 
    echo "      -b  Compile and build only SparkBench suite" 
    echo "      -c  Clean Spark and SparkBench suite"
    echo "      -h  Show usage"
    echo

    exit 1
}

prepare_certificates() {
  cp -r ../util/certificates/lib "${JAVA_HOME}"/../

  # Create the security directory if it does not exist
  if [ ! -d "${JAVA_HOME}/lib/security/" ]
  then 
    mkdir -p "${JAVA_HOME}"/lib/security
  fi 

  cp ../util/certificates/blacklisted.certs "${JAVA_HOME}"/lib/security/
  cp ../util/certificates/cacerts "${JAVA_HOME}"/lib/security/
  cp ../util/certificates/nss.cfg "${JAVA_HOME}"/lib/security/
  cp ../util/certificates/java.policy "${JAVA_HOME}"/lib/security/
  cp ../util/certificates/java.security "${JAVA_HOME}"/lib/security/
}

build_spark() {
  cd "${SPARK_DIR}" || exit
  # Do not use parallel compilation. Spark3.3.0 freeze during
  # compilation. 
  ./build/mvn -DskipTests clean package >> "${COMPILE_OUT}" 2>&1
  retValue=$?
  message="Build Spark" 
  check ${retValue} "${message}"
  cd - > /dev/null || exit
}

install_spark() {
  cd "${SPARK_DIR}" || exit
  ./build/mvn -DskipTests clean install >> "${COMPILE_OUT}" 2>&1
  retValue=$?
  message="Install Spark" 
  check ${retValue} "${message}"
  cd - > /dev/null || exit
}

benchmark_dependencies() {
  if [[ ! -n $(find "${HOME}"/.m2 -name "wikixmlj*") ]]
  then 
    git clone  https://github.com/synhershko/wikixmlj.git >> "${COMPILE_OUT}" 2>&1

    cd wikixmlj || exit
    mvn package -Dmaven.test.skip=true >> "${COMPILE_OUT}" 2>&1
    mvn install -Dmaven.test.skip=true >> "${COMPILE_OUT}" 2>&1
    cd - >> "${COMPILE_OUT}" 2>&1 || exit

    rm -rf ./wikixmlj >> "${COMPILE_OUT}" 2>&1
  fi
}

build_benchmarks() {
  ./spark-bench/bin/build-all.sh "spark3.3.0" >> "${COMPILE_OUT}" 2>&1
  retValue=$?
  message="Build Spark Benchmarks" 
  check ${retValue} "${message}"
}

build_spark_tpcds() {
  if [[ ! -d ./spark-tpcds ]]
  then
    git clone git@github.com:jackkolokasis/spark-tpcds.git >> "${COMPILE_OUT}" 2>&1 
  fi

  cd ./spark-tpcds || exit
  ./gradlew jar >> "${COMPILE_OUT}" 2>&1 
  retValue=$?
  message="Build Spark TPC-DS" 
  check ${retValue} "${message}"
  cd - > /dev/null || exit
}

clean_all() {
  cd "${SPARK_DIR}" || exit
  ./build/mvn clean >> "${COMPILE_OUT}" 2>&1
  
  retValue=$?
  message="Clean Spark" 
  check ${retValue} "${message}"

  cd - >> "${COMPILE_OUT}" 2>&1 || exit

  cd ./spark-bench || exit
  mvn clean >> "${COMPILE_OUT}" 2>&1

  retValue=$?
  message="Clean SparkBench suite" 
  check ${retValue} "${message}"

  cd - >> "${COMPILE_OUT}" 2>&1 || exit
}

# Check for the input arguments
while getopts "asbich" opt
do

  echo "-----------------------------------"
  echo "Compilation output messages are here: ${COMPILE_OUT}"
  echo "-----------------------------------"
  echo 

  case "${opt}" in
    a)
      create_cgexec
      prepare_certificates
      build_spark
      benchmark_dependencies
      build_benchmarks
      build_spark_tpcds
      ;;
    s)
      create_cgexec
      prepare_certificates
      build_spark
      ;;
    b)
      create_cgexec
      benchmark_dependencies
      build_benchmarks
      build_spark_tpcds
      ;;
    i)
      create_cgexec
      prepare_certificates
      install_spark
      ;;
    c)
      clean_all
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done
