echo export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH


ODIN="../odin/odin"
PROJECT="src"
TARGET="linux"

compile_cmd=("$ODIN" run "$PROJECT")

if [[ "$TARGET" = "linux" ]]; then

	rpath_var='$ORIGIN/lib'
	runtime_lib_flag="-Wl,-rpath,'$rpath_var'"
	compile_lib_flag="-L$INSTALL_PATH/lib"
	compile_cmd+=(
		-extra-linker-flags:"$compile_lib_flag $runtime_lib_flag"
	)
fi

echo "${compile_cmd[@]}"
"${compile_cmd[@]}"
