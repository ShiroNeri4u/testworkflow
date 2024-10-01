function InitToolkit () {

  DefClass=""

  function @DefClass() {
    DefClass="$1"
    eval _Class_${DefClass}_Attributes=""
    eval _Class_${DefClass}_Methods="\"${DefClass}::${DefClass} \""
    eval "${DefClass}::${DefClass} () { return 0; }"
    if [ "$#" = "3" -a "$2" = ":" ]; then
      eval local _ParentAttributes=\$_Class_$3_Attributes
      eval local _Attributes=_Class_${DefClass}_Attributes
      eval $_Attributes=\"\${$_Attributes}${_ParentAttributes} \"
      eval local _ParentMethods=\$_Class_$3_Methods
      eval local _Methods=_Class_${DefClass}_Methods
      eval $_Methods=\"\${$_Methods}${_ParentMethods} \"
    fi
  }

  function @DefAttribute () {
    local _Attributes="_Class_${DefClass}_Attributes"
    eval $_Attributes=\"\${$_Attributes}$1 \"
  }

  function @DefMethod () {
    local _Methods="_Class_${DefClass}_Methods"
    eval $_Methods=\"\${$_Methods}${DefClass}::$1 \"
  }

  function _LoadAttributes () {
    eval local _Attributes=\"\$_Class_${_Class}_Attributes\"
    local _Attribute
    for _Attribute in $_Attributes; do
      eval this_${_Attribute}=\"\$_Instance_${_Instance}_${_Attribute}\"
    done
  }

  function _LoadMethods () {
    eval local _Methods=\"\$_Class_${_Class}_Methods\"
    local _OriginalMethod
    for _OriginalMethod in $_Methods; do
      local _Method=$(_MethodName $_OriginalMethod)
      eval "this.${_Method} () { ${_OriginalMethod} \"\$@\"; return \$?; }"
    done
  }

  function _SaveAttributes () {
    eval local _Attributes=\"\$_Class_${_Class}_Attributes\"
    local _Attribute
    for _Attribute in $_Attributes; do
      eval _Instance_${_Instance}_${_Attribute}=\"\$this_${_Attribute}\"
      unset -v this_${_Attribute}
    done
  }

  function _ClearMethods () {
    eval local _Methods=\"\$_Class_${_Class}_Methods\"
    local _OriginalMethod
    for _OriginalMethod in $_Methods; do
      local _Method=$(_MethodName $_OriginalMethod)
      unset -f this.${_Method}
    done
  }

  function _MethodName () {
    echo $1 | awk -F :: '{print $2}'
  }

  function @TypeOf () {
    eval echo \$_TypeOf_$1
  }

  function @New () {
    local _instance="$(uuidgen | tr A-F a-f | sed -e "s/-//g")$(date +%s%3N)"
    local _class=$1
    local _object=$2
    shift 2
    eval _TypeOf_${_instance}=$_class
    eval ${_object}=$_instance
    local _originalmethod
    eval local _methods=\"\$_Class_${_class}_Methods\"
    for _originalmethod in $_methods; do
      local _method=$(_MethodName $_originalmethod)
      eval "${_object}.${_method} () { local _Instance=$_instance; local _Class=$_class; _LoadAttributes; _LoadMethods; ${_originalmethod} \"\$@\"; local rt=\$?; _SaveAttributes; _ClearMethods; return $rt; }"
    done
    eval ${_object}.${_class} \"\$@\" || true
  }
 
  function @Destory () {
  eval local _instance=\$$1
  eval local _class=\$_TypeOf_${_instance}
  eval local _attributes=\$_Class_${_class}_Attributes
  eval local _methods=\$_Class_${_class}_Methods
  unset $1
  unset _TypeOf_${_instance}
  local _attribute
  for _attribute in $_attributes; do
    unset -v Instance_${_instance}_${_attribute}
  done
  local _originalmethod
  for _originalmethod in $_methods; do
    local method=$(_MethodName $_originalmethod)
    unset -f $1.$method
  done
  }

}

InitToolkit
BASICDIR=$PWD

@DefClass Package
 @DefAttribute PackageName
 @DefAttribute PackageVersion
 @DefAttribute Link
 @DefAttribute TargetArch
 @DefAttribute TargetAPI
 @DefMethod Clone
 @DefMethod Download
 @DefMethod BuildEnv

 Package::Package () {
  this_PackageName=$1
  this_PackageVersion=$2
  this_Link=$3
  this_TargetArch=$4
  this_TargetAPI=$5
 }

  Package::Clone () {
   git clone $this_Link
  }

  Package::Download () {
   wget $this_Link
  }

  Package::BuildEnv () {
    # SetUp Env
    pip3 install crossenv
    export ARCH=$this_TargetArch
    export ANDROID_API=$this_TargetAPI
    export PATH=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
    export ANDROID_NDK_HOME=$ANDROID_NDK
    export CC=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${this_TargetArch}-linux-android21-clang
    export CXX=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${this_TargetArch}-linux-android21-clang++
    export AS=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-as
    export AR=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
    export STRIP=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
    export SYSROOT=$BASICDIR/python3-android/src/Python-3.7.6/Android/sysroot/usr
    export CFLAG="-D__ANDROID_API__=$ANDROID_API -Os -fPIC -DANDROID "
    export LDFLAG="-lc -lm -ldl -llog "
    #Download ffmpeg
    wget https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz
    tar xvf ffmpeg-7.1.tar.xz
    ffmpeg-7.1/configure --enable-small --disable-shared --enable-static --enable-pthreads --ignore-tests=TEST --target-os=android --prefix=$SYSROOT --enable-openssl --enable-cross-compile --sysroot=$SYSROOT --cc=$CC --cxx=$CXX --ar=$AR --as=$AS --arch=$ARCH --extra-cflags="$CFLAG"
    make -j8 && make install
  
    cd ..
    python3 -m crossenv $BASICDIR/python3-android/build/usr/bin/python3 cross_venv
    cd cross_venv/cross/bin
    source activate
    python3 -m ensurepip --upgrade
    python -m pip install --upgrade pip
    pip3 install Cython
    mkdir -p $BASICDIR/crosslib
    pip3 wheel --wheel-dir $BASICDIR/crosslib -r $BASICDIR/requirements.txt
  }

@DefClass Python : Package
 @DefMethod Build
 Python::Python () {
  this.Package $@
 }

 Python::Build () {
  # Patch
  sed -i "s/PYVER=.*/PYVER=$this_PackageVersion/" build.sh
  sed -i '12,22d' Android/bldlibrary.patch
  sed -i "s/choices=range(30, 40)/choices=range(21, 40)/" Android/util.py
  sed -i 's/https:\/\/ftp.gnu.org/http:\/\/ftp.nluug.nl\/ftp/g' Android/build_deps.py
  sed -i 's/ncurses-6.4/ncurses-6.5/' Android/build_deps.py
  sed -i 's/v2.39\/util-linux-2.39.2/v2.40\/util-linux-2.40.2/' Android/build_deps.py
  sed -i 's/v3.4.4\/libffi-3.4.4/v3.4.6\/libffi-3.4.6/' Android/build_deps.py
  sed -i 's/gdbm-1.23/gdbm-1.24/' Android/build_deps.py
  sed -i 's/https:\/\/www.openssl.org\/source\/openssl-3.0.12.tar.gz/https:\/\/github.com\/openssl\/openssl\/releases\/download\/OpenSSL_1_1_1w\/openssl-1.1.1w.tar.gz/' Android/build_deps.py
  sed -i 's/3460000/3460100/' Android/build_deps.py
  # SetUp Env
  export ARCH=$this_TargetArch
  export ANDROID_API=$this_TargetAPI
  export PATH=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
  export ANDROID_NDK_HOME=$ANDROID_NDK
  export CC=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang
  export CXX=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang++
  export AS=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-as
  export AR=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
  # Build
  ./build.sh
 }

#Build Python
@New Python python Python 3.7.6 https://github.com/GRRedWings/python3-android arm64 21

python.Clone && cd python3-android && python.Build

cd $BASICDIR

@New Package Libs Libs 0 https://raw.githubusercontent.com/LmeSzinc/AzurLaneAutoScript/refs/heads/master/requirements.txt aarch64 21
Libs.Download && Libs.BuildEnv