#!/bin/zsh
# Starts a fake webOS TV on 127.0.0.1 for manual testing: SSH on 9922 (users prisoner and root,
# legacy algorithms, no PTY) and the Key Server on 9991 (passphrase A1B2C3). Everything lives in
# /tmp/faketv; generated keys are throwaway.
set -eu
SRC=${0:A:h}
T=/tmp/faketv
mkdir -p $T/bin $T/keyserver $T/home/apps/com.example.demo $T/media/developer \
  $T/var/luna/preferences $T/var/log $T/tmpvar/log/reports/librdx
cd $T || exit 1
[[ -d venv ]] || python3 -m venv venv
venv/bin/pip -q install 'paramiko<4'
[[ -f host_rsa ]] || openssl genrsa -traditional -out host_rsa 2048 2>/dev/null
if [[ ! -f tvkey.pem ]]; then
  openssl genrsa -traditional -out tvkey.pem 2048 2>/dev/null
  openssl rsa -traditional -aes128 -passout pass:A1B2C3 -in tvkey.pem -out keyserver/webos_rsa 2>/dev/null
fi
cp $SRC/mock_tv.py $SRC/luna.py $T/
cp luna.py bin/luna.py; chmod +x bin/luna.py
printf '#!/bin/sh\nexec /tmp/faketv/bin/luna.py "$@"\n' > bin/luna-send-pub
cp bin/luna-send-pub bin/luna-send
printf '#!/bin/sh\nwhile :; do echo "kern  :warn  : [   1.5] usb: heartbeat"; sleep 1; done\n' > bin/dmesg
printf '#!/bin/sh\necho "PmLogCtl: Context '"'"'com.foo'"'"' = info"\necho "PmLogCtl: Context '"'"'com.bar'"'"' = err"\n' > bin/PmLogCtl
cat > bin/ls-monitor <<'MON'
#!/bin/sh
echo '{"type":"call","transport":"TX","token":5,"senderUniqueName":"s","sender":"com.a","destination":"com.b","methodCategory":"/x","method":"go","payload":{"k":1}}'
sleep 60
MON
chmod +x bin/*
printf 'abc123FAKEtoken' > var/luna/preferences/devmode_enabled
echo 'ciao dalla tv' > home/nota.txt
for i in 1 2 3 4 5; do echo "2026-10-31T01:0$i:00.000000Z [12.$i] user.err proc$i [1:2] ctx MSG {\"a\":1} syslog riga $i"; done > var/log/messages
printf 'Segmentation fault\nbacktrace: main+0x12\n' | gzip > "tmpvar/log/reports/librdx/x$(printf '\001')usr$(printf '\001')palm$(printf '\001')applications$(printf '\001')com.example.demo$(printf '\001')bin$(printf '\001')main____main.123.456.gz"
python3 $SRC/make_apps.py $SRC/apps.json $T
rm -f apps.json installed.log
pkill -f mock_tv.py || true
pkill -f 'http.server 9991' || true
nohup venv/bin/python -u mock_tv.py > mock.log 2>&1 &
nohup python3 -m http.server 9991 --bind 127.0.0.1 --directory $T/keyserver > http.log 2>&1 &
