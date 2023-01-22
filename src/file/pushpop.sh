function pushd () {
    command pushd "$@" > /dev/null;
    return $?;
}

function popd () {
    command popd "$@" > /dev/null;
    return $?;
}
