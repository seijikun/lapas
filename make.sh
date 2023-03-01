#!/bin/bash

pushd bin/keepEngine;
cargo build --target x86_64-unknown-linux-musl --release || exit $?;
popd;
cp bin/keepEngine/target/x86_64-unknown-linux-musl/release/keepEngine res/lapas/guest/lapas/keepEngine || exit $?;
chmod +x res/lapas/guest/lapas/keepEngine;


pushd bin/lapas_api_server;
cargo build --target x86_64-unknown-linux-musl --release || exit $?;
popd;
cp bin/lapas_api_server/target/x86_64-unknown-linux-musl/release/lapas-api-server res/lapas/scripts/lapas-api-server || exit $?;
chmod +x res/lapas/scripts/lapas-api-server;


pushd bin/lapas_api_client;
cargo build --target x86_64-unknown-linux-musl --release || exit $?;
popd;
cp bin/lapas_api_client/target/x86_64-unknown-linux-musl/release/lapas-api-client res/lapas/guest/lapas/lapas-api-client || exit $?;
chmod a+x res/lapas/guest/lapas/lapas-api-client;


# package installer script
python3 ./make.py > ./lapas_installer.sh
