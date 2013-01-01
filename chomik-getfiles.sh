#!/bin/bash
# 
#  Save 'directory' from chomikuj.pl at specified level
# 
#  Script works on cookies.txt, prepare them as Netscape cookie format with 
#  those keys and theirs respective values
#  Global cookies (valued <> 0 for the epoch):
#    guid, RememberMe, __RequestVerificationToken_Lw__
# 
#  Session cookies (valued 0 as the valid to epoch):
#    ChomikSession, spt, loc 
# 
#  Adjust downloadedPath to suit your download directory.
# 
#  Function encodeParam is borrowed, haven't written it.
# 
#  Current working version dated 4 Dec 2012.
#
#  Sign off, Przemek Lipka (lipka@clazz.pl) 

function encodeParam() {
  local LANG=en_US.ISO8859-1 ch i
    for ((i=0;i<${#1};i++)); do
        ch="${1:i:1}"
        [[ $ch =~ [._~A-Za-z0-9-] ]] && echo -n "$ch" || printf "%%%02X" "'$ch"
    done
}

function pause() {
  read -p "$*" THROW_AWAY
}

function encodeUTF8() {
 echo "$*" | sed -e 's/\*e2\*80\*99/''/g' \
                 -e 's/\*c5\*82/ł/g'      \
                 -e 's/\*c5\*81/Ł/g'      \
                 -e 's/\*c5\*9b/ś/g'      \
                 -e 's/\*c4\*87/ć/g'      \
                 -e 's/\*c4\*84/ń/g'      \
                 -e 's/\*c4\*85/ą/g'      \
                 -e 's/\*c4\*99/ę/g'      \
                 -e 's/\*c3\*b3/ó/g'      \
                 -e 's/*5b/(/g'           \
                 -e 's/*5d/)/g'           \
                 -e 's/*2c/,/g'           \
                 -e 's/+/ /g'
}

# Directories
downloadedPath='/home/elpe/chomik'

# Temporary files created in /tmp
XHRResponse=$(mktemp)

serveFile='http://chomikuj.pl/action/License/Download'
acceptLargeTransfer='http://chomikuj.pl/action/License/acceptLargeTransfer'

# Constants
XHRHeader='X-Requested-With: XMLHttpRequest'
mozillaBrowser='Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:14.0) Gecko/20100101 Firefox/14.0.1)'

# XXX: start the tool based on the input file line by line
while read nextElement; do
# echo -n "Pobieranie zawartosci katalogu... ${nextElement} "

directoryList=$(mktemp)

# File is unique so i don't need to delete it
# rm $directoryList 2> /dev/null

wget --user-agent="${mozillaBrowser}"  \
     --quiet                           \
     --load-cookies=cookies.txt        \
     --output-document=$directoryList  \
     "http://chomikuj.pl${nextElement}"

# in case of multipage strip page number
nextElement=$(echo $nextElement  | sed -re 's/,[[:digit:]]+$//')
directoryName=$(encodeUTF8 $(echo $nextElement | sed -re 's/.*\/([^\/]*)$/\1/' ))

requestToken=$(grep "__RequestVerificationToken" $directoryList | sed -n 's/.*value="//; s/".*//; s/\//%2F/p')
requestTokenEncoded=$(encodeParam $requestToken)

filesList=( $(grep -F $nextElement $directoryList |  grep -oP '(?<=,)[0-9]+(?=\.)' | sort -u) )

# creation of directory, named just as in chomikuj
mkdir -p "${downloadedPath}/${directoryName}"

for fileId in "${filesList[@]}"
do
flatPostData="fileId=${fileId}&__RequestVerificationToken=${requestTokenEncoded}"

wget --user-agent="${mozillaBrowser}" \
     --post-data=${flatPostData}      \
     --load-cookies=cookies.txt       \
     --header="${XHRHeader}"          \
     --quiet                          \
     --output-document=$XHRResponse   \
     $serveFile

# large files require confirmation
if [[ -n $(grep -o 'orgFile\|userSelection' $XHRResponse) ]]; 
then  
orgFile=$(sed -e 's/.*orgFile\\" value=\\"//; s/\\".*//;' $XHRResponse)
userSelection=$(sed -e 's/.*userSelection\\" value=\\"//; s/\\".*//;' $XHRResponse)

# sending once again
flatPostData="${flatPostData}&orgFile=${orgFile}&userSelection=${userSelection}"

wget --user-agent="${mozillaBrowser}" \
     --post-data=${flatPostData}      \
     --load-cookies=cookies.txt       \
     --header="${XHRHeader}"          \
     --quiet                          \
     --output-document=$XHRResponse   \
     $acceptLargeTransfer

fi

payload=$(sed -e 's/.*href=\\"http:\/\///; s/\\".*//;' $XHRResponse) || exit 1

tempFilePath=$(mktemp)

wget --limit-rate=200k           \
     --waitretry=20              \
     --output-document=$tempFilePath \
     $payload

fileName=$(encodeUTF8 $(grep -m 1 -o "/.*,${fileId}[^\"]*\"" $directoryList | sed -re "s/.*\/([^\/]+)+,${fileId}.([^\"]+)\".*/\1.\2/" )) || exit 1

mv $tempFilePath "${downloadedPath}/${directoryName}/${fileName}"
done

done < daily_download.txt
# End of the loop and the program itself
