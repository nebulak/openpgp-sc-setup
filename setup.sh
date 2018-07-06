# Get smartcard pin
echo_n "Enter PIN for your smartcard:"
read -s -p "Pin: " PASSWORD; echo
read -s -p "Confirm Pin: " PASSCONFIRM; echo

if [[ "$PASSWORD" != "$PASSCONFIRM" ]]; then
 echo "Pins do not match, exiting..."
 echo "Restart this script and try again!"
 exit -1
fi

# Generate the key
gpg --batch --gen-key gen-key-parameters

# Export Key
gpg --export --armor "openpgp-sc <openpgp@smartcard.org>" > /tmp/key.asc

# reset smartcard
gpg-connect-agent < ./reset.txt

# Setup smartcard pin
# //TODO: change admin pin
gpg --change-pin < "1\n$PASSWORD\n$PASSWORD\n1\n$PASSWORD\n$PASSWORD\n"

# Copy key to card
gpg --expert --edit-key "openpgp-sc <openpgp@smartcard.org>" < "toggle\nkey 1\nkeytocard\nkey 2\nkeytocard"


# Import into root keyring
su root
gpg --import /tmp/key.asc

# generate key for luks
mkdir -m 700 /etc/keys
dd if=/dev/random bs=1 count=256 | gpg -e -o /etc/keys/cryptkey.gpg -r "openpgp-sc <openpgp@smartcard.org>" -ec
cd /root
mkfifo -m 700 keyfifo
gpg -d /etc/keys/cryptkey.gpg >keyfifo

# add luks key
cd /root
cryptsetup luksAddKey /dev/sda1 keyfifo
cryptsetup luksAddKey /dev/sda2 keyfifo

# kill scdaemon
killall -9 scdaemon

# remove keyfifo
rm keyfifo
gpg --export-options export-minimal --export {YOURKEYID} | gpg \
      --no-default-keyring --keyring /etc/keys/pubring.gpg \
      --secret-keyring /etc/keys/secring.gpg --import
gpg --no-default-keyring --keyring /etc/keys/pubring.gpg \
      --secret-keyring /etc/keys/secring.gpg --card-status

# update crypttab
sed 's/none luks/\/etc\/keys\/cryptkey.gpg luks,keyscript=decrypt_gnupg_sc/g' "/etc/crypttab"

# copy decrypt scripts
cp ./decrypt_gnupg_sc /lib/cryptsetup/scripts/decrypt_gnupg_sc
chmod 755 /lib/cryptsetup/scripts/decrypt_gnupg_sc
cp ./cryptgnupg_sc /etc/initramfs-tools/hooks/cryptgnupg_sc
chmod 755 /etc/initramfs-tools/hooks/cryptgnupg_sc

# //TODO: backup initramdisk

# generate initramfs
update-initramfs -u
