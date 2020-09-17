set -e
ABI="armeabi-v7a"
OPENMP="ON"
VULKAN="ON"
OPENCL="ON"
OPENGL="ON"
RUN_LOOP=100
FORWARD_TYPE=0
CLEAN=""
PUSH_MODEL=""
BIN=benchmark.out

WORK_DIR=`pwd`
BUILD_DIR=build
# BUILD_DIR=/Users/hussamlawen/work/MNN/project/android/build_64
BENCHMARK_MODEL_DIR=$WORK_DIR/ofa_bench
# BENCHMARK_MODEL_DIR=/Users/hussamlawen/work/fp32
# BENCHMARK_FILE_NAME=benchmark.txt
# BENCHMARK_MODEL_DIR=/Users/hussamlawen/work/ofa_lut/lut_mnn
ANDROID_DIR=/data/local/tmp

DEVICE_ID=""

function usage() {
    echo "-64\tBuild 64bit."
    echo "-c\tClean up build folders."
    echo "-p\tPush models to device"
}
function die() {
    echo $1
    exit 1
}

function clean_build() {
    echo $1 | grep "$BUILD_DIR\b" > /dev/null
    if [[ "$?" != "0" ]]; then
        die "Warnning: $1 seems not to be a BUILD folder."
    fi
    rm -rf $1
    mkdir $1
}

function build_android_bench() {
    if [ "-c" == "$CLEAN" ]; then
        clean_build $BUILD_DIR
    fi
    if [ "$ABI" != "arm64-v8a" ]; then
      mkdir -p build
    else
      mkdir -p build_64
    fi
    cd $BUILD_DIR
    cmake ../../ \
          -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
          -DCMAKE_BUILD_TYPE=Release \
          -DANDROID_ABI="${ABI}" \
          -DANDROID_STL=c++_static \
          -DCMAKE_BUILD_TYPE=Release \
          -DANDROID_NATIVE_API_LEVEL=android-21  \
          -DANDROID_TOOLCHAIN=clang \
          -DMNN_VULKAN:BOOL=$VULKAN \
          -DMNN_OPENCL:BOOL=$OPENCL \
          -DMNN_OPENMP:BOOL=$OPENMP \
          -DMNN_OPENGL:BOOL=$OPENGL \
          -DMNN_USE_THREAD_POOL=OFF \
          -DMNN_DEBUG:BOOL=OFF \
          -DMNN_BUILD_BENCHMARK:BOOL=ON \
          -DMNN_BUILD_FOR_ANDROID_COMMAND=true \
          -DNATIVE_LIBRARY_OUTPUT=.
    make -j8 benchmark.out timeProfile.out create_lut.out
}

function bench_android() {
    if [ "$ABI" != "arm64-v8a" ]; then
        echo $ABI
        build_android_bench
    else
        echo $BUILD_DIR
        # cd $BUILD_DIR
        build_android_bench
    fi

    find . -name "*.so" | while read solib; do
        adb -s $DEVICE_ID push $solib  $ANDROID_DIR
    done
    adb -s $DEVICE_ID push benchmark.out $ANDROID_DIR
    adb -s $DEVICE_ID push create_lut.out $ANDROID_DIR
    adb -s $DEVICE_ID push timeProfile.out $ANDROID_DIR
    adb -s $DEVICE_ID shell chmod 0777 $ANDROID_DIR/benchmark.out
    adb -s $DEVICE_ID shell chmod 0777 $ANDROID_DIR/create_lut.out

    if [ "" != "$PUSH_MODEL" ]; then
        adb -s $DEVICE_ID shell "rm -rf $ANDROID_DIR/benchmark_models"
        adb -s $DEVICE_ID push $BENCHMARK_MODEL_DIR $ANDROID_DIR/benchmark_models
    fi
    # adb -s $DEVICE_ID shell "cat /proc/cpuinfo > $ANDROID_DIR/benchmark.txt"
    BENCHMARK_FILE_NAME=$(adb -s $DEVICE_ID shell getprop ro.product.model)

    BENCHMARK_FILE_NAME=${BENCHMARK_FILE_NAME// /_}
    # BENCHMARK_FILE_NAME="${BENCHMARK_FILE_NAME}_benchmark.txt"
    soc_code=$(adb -s $DEVICE_ID shell getprop ro.product.board)

    soc_code=$(grep -Eo -A 2 \"$soc_code\" ../database.json | grep -o '"[^"]*"$' | sed -n 2p | xargs | sed 's/ /_/g')  #grep -o '\"SoC\":.*' | sed 's/"/\_/g')

    echo $soc_code

    if [ "$BIN" != "create_lut.out" ]; then
      BENCHMARK_FILE_NAME="${BENCHMARK_FILE_NAME}_${soc_code}_benchmark.txt"
      echo $BENCHMARK_FILE_NAME
      adb -s $DEVICE_ID shell "rm -f $ANDROID_DIR/$BENCHMARK_FILE_NAME"
      adb -s $DEVICE_ID shell "echo >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"
      adb -s $DEVICE_ID shell "echo Build Flags: ABI=$ABI  OpenMP=$OPENMP Vulkan=$VULKAN OpenCL=$OPENCL >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"

      #benchmark  CPU
      adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 $FORWARD_TYPE 4 2 >$ANDROID_DIR/benchmark.err >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"
      # echo "Vulkan"
      #benchmark  Vulkan
      # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 7 4 2> $ANDROID_DIR/benchmark.err >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"
      #benchmark OpenGL
      # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 6 4 2 >$ANDROID_DIR/benchmark.err >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"
      #benchmark OpenCL
      # echo "OpenCL"
      # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 3 4 2 >$ANDROID_DIR/benchmark.err >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"
      #benchmark Auto
      # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 4 4 2 >$ANDROID_DIR/benchmark.err >> $ANDROID_DIR/$BENCHMARK_FILE_NAME"

      adb -s $DEVICE_ID pull $ANDROID_DIR/$BENCHMARK_FILE_NAME ../
    else
      LUT_FOLDER="$ANDROID_DIR/${BENCHMARK_FILE_NAME}_${soc_code}_lut"
      adb -s $DEVICE_ID shell "rm -rf $LUT_FOLDER"
      adb -s $DEVICE_ID shell "mkdir $LUT_FOLDER"
      for i in `seq 160 16 224`;
        do
          echo $i
          BENCHMARK_FILE_NAME="${i}_lookup_table.yaml"
          adb -s $DEVICE_ID shell "echo >> $LUT_FOLDER/$BENCHMARK_FILE_NAME"

          #benchmark  CPU
          adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models/$i $RUN_LOOP 10 $FORWARD_TYPE 4 2 $i >$ANDROID_DIR/benchmark.err >> $LUT_FOLDER/$BENCHMARK_FILE_NAME"

          #benchmark  Vulkan
          # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 7 4 2 $i >$LUT_FOLDER/lut.err >> $LUT_FOLDER/$BENCHMARK_FILE_NAME"
          #benchmark OpenGL
          # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 6 4 2 $i >$LUT_FOLDER/lut.err >> $LUT_FOLDER/$BENCHMARK_FILE_NAME"
          #benchmark OpenCL
          # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 3 4 2 $i >$LUT_FOLDER/lut.err >> $LUT_FOLDER/$BENCHMARK_FILE_NAME"
          #benchmark Auto
          # adb -s $DEVICE_ID shell "LD_LIBRARY_PATH=$ANDROID_DIR $ANDROID_DIR/$BIN $ANDROID_DIR/benchmark_models $RUN_LOOP 10 4 4 2 $i >$LUT_FOLDER/lut.err >> $LUT_FOLDER/$BENCHMARK_FILE_NAME"

          adb -s $DEVICE_ID pull $LUT_FOLDER ../
        done
    fi



}
# PUSH_MODEL="-p"
while [ "$1" != "" ]; do
    case $1 in
        -64)
            shift
            ABI="arm64-v8a"
            # BUILD_DIR=/Users/hussamlawen/work/MNN/project/android/build_64
            BUILD_DIR=build_64
            ;;
        -c)
            shift
            CLEAN="-c"
            ;;
        -p)
            shift
            PUSH_MODEL="-p"
            ;;
        -d)
            shift
            echo $1
            DEVICE_ID=$1
            shift
            ;;
        -lut)
            shift
            BIN=create_lut.out
            # BENCHMARK_MODEL_DIR=/Users/hussamlawen/work/ofa_lut/lut2/lut_mnn
            # BENCHMARK_MODEL_DIR=/Users/hussamlawen/work/multi_res_luts/mnn
            BENCHMARK_MODEL_DIR=/Users/hussamlawen/work/multi_res_luts/lut2/mnn
            # BENCHMARK_MODEL_DIR=/Users/hussamlawen/work/ofa_lut/lut2/oneplus8_lut_extra
            ;;
        *)
            # echo $1
            usage
            exit 1
    esac
done

bench_android
