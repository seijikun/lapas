function getOpenSuseTumbleweedImgName {
	URL="https://download.opensuse.org/download/tumbleweed/appliances/?jsontable"

	curl -s "$URL" \
	| jq -r '
		.data[]
		| select(.name | test("^openSUSE-Tumbleweed-[0-9]+\\.x86_64\\.tar\\.xz$"))
		| [.mtime, .name]
		| @tsv
		' \
	| sort -nr \
	| head -n1 \
	| cut -f2
}
