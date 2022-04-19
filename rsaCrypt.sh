#!/bin/bash 

SEPARATOR="___"
COMMENT="###"
OPTS="-aes-256-cbc -md sha512 -pbkdf2 -iter 100000 -salt"
VERSION=1.0.0

encrypt() {

	file=$2;
	PUBLIC_KEY="$1"

	# Creating temporary files for encryption
	TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/$(basename "$0").XXXXXX.out")"
	TMP_KEY="$(mktemp "${TMPDIR:-/tmp}/$(basename "$0").XXXXXX.key")"
	trap 'shred "$TMP_OUT" "$TMP_KEY"; rm -rf "$TMP_OUT" "$TMP_KEY" ' EXIT SIGINT


	# Generating random secret for file encryption 
	openssl rand -base64 64 > "$TMP_KEY";

	echo -e "Encrypted with $0 version $VERSION using the following key : \n$(cat $PUBLIC_KEY) " | openssl base64 > "$TMP_OUT"
	echo $COMMENT >> "$TMP_OUT"

	# Crypt the secret key with public key
	openssl rsautl -encrypt -pubin -inkey <(ssh-keygen -f "$PUBLIC_KEY" -e -m PKCS8) -ssl -in "$TMP_KEY" | openssl base64 >> "$TMP_OUT"; 
	# Add a separator between parts of the file
	echo "$SEPARATOR" >> "$TMP_OUT"; 

	# Crypt the original file with the secret key
	openssl enc $OPTS -in $file -pass file:"$TMP_KEY" | openssl base64 >> "$TMP_OUT"

	outfile="${file}.enc"
	cat "$TMP_OUT" > $outfile

}


decrypt () {

	file=$2
	key=$1
	lines=$(wc -l < $file)

	# Creating temporary files for encryption
	TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/$(basename "$0").XXXXXX.out")"
	TMP_KEY="$(mktemp "${TMPDIR:-/tmp}/$(basename "$0").XXXXXX.key")"
	trap 'shred "$TMP_OUT" "$TMP_KEY" && rm -rf "$TMP_OUT" "$TMP_KEY" ' EXIT SIGINT

	# Get the comment part
	grep -B $lines "$COMMENT" $file | grep -v "$COMMENT" | openssl base64 -d

	# Get the key part
	grep -B $lines "$SEPARATOR" $file | grep -v "$SEPARATOR" | grep -A $lines "$COMMENT" | grep -v "$COMMENT" | openssl base64 -d > "$TMP_OUT"

	# Try to decrypt the key
	openssl rsautl -decrypt -inkey "$key" -in "$TMP_OUT" -out "$TMP_KEY" 2> /dev/null

	if  [[ $? -ne 0 ]] ; then

		# If decryption failed, it might be because of wrong key format
		echo "Decryption failed , reencoding key" >&2

		# Change openssh key to RSA
		cp $key "$TMP_KEY"
		ssh-keygen -f "$TMP_KEY" -p -N "" -m pem

		# Decrypt the key again with the PEM key
		openssl rsautl -decrypt -inkey "$TMP_KEY" -in "$TMP_OUT" -out "$TMP_KEY"

	fi

	# Get the crypted file part
	grep -A $lines "$SEPARATOR" $file | grep -v "$SEPARATOR" | openssl base64 -d > "$TMP_OUT"
	outfile=${file%.enc}

	# Decrypting the file contents
	openssl enc -d -aes-256-cbc $OPTS -in "$TMP_OUT" -pass file:"$TMP_KEY" > $outfile

}

retrieve_keys() {
	(curl -sf "https://gitlab.com/${1}.keys" | grep 'ssh-rsa' | head -n 1 && echo) > "$HOME/.ssh/$1.pub"

	if [[ "$(grep ^ssh < "$HOME/.ssh/$1.pub" | wc -l)" -lt 1 ]]; then
		echo "Could not find any SSH key for $1" >&2
		exit 1
	fi
}

usage() {
cat <<HERE
  USAGE:
    Encryption : produces file.enc
    $0 -e <-i public_key_file | -g gitlab handle> <file> 
    Decryption : produces file
    $0 [-i secret_key_file] <file.enc> 
HERE
exit;
}



if [[ "$#" -lt 1 ]] ; then 
	echo "Wrong number of arguments"
	usage ; 
fi ;

mode="decrypt"
KEY=""

while getopts "ei:g:" option; do
	case "${option}" in
		i)
			if [[ -r "${OPTARG}" ]] ; then
				echo "Using key file ${OPTARG}" >& 2
				KEY=${OPTARG}
			else
				echo "Unable to open key file ${OPTARG}"
				usage
			fi
			;;
		g)
			retrieve_keys ${OPTARG}
			KEY="$HOME/.ssh/${OPTARG}.pub"
			;;
		e)
			mode="crypt"
			;;
	esac
done
shift $((OPTIND-1))

file=$1;

if [[ "$mode" = "crypt"  ]]; then
	if ! [[ -e "$KEY" ]]; then
		echo "Unable to open public key file $KEY"
		usage 
	fi;
	encrypt "$KEY" "$file"
elif [[ "$mode" = "decrypt" ]]; then
	if ! [[ -r "$KEY" ]]; then
		KEY="$HOME/.ssh/id_rsa"
		echo "Loading default private key file $KEY" >& 2
	fi;
	decrypt "$KEY" "$file"
else
	echo "Wrong mode $mode"
	usage
fi;

