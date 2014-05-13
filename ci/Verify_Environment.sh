set -e

echo "Checking zlib-devel installed"
rpm -q zlib-devel

echo "Checking openssl-devel installed"
rpm -q openssl-devel

echo "Checking libxml2-devel installed"
rpm -q libxml2-devel

echo "Checking libxslt-devel installed"
rpm -q libxslt-devel

echo "Checking git atleast 1.8"
if git --version | grep -q "1.8"; then
    echo "Git 1.8 found"
else
    echo "Git 1.8 not found"
    exit 1;
fi

echo "Making sure 'ruby' is on path."
type ruby

echo "Making sure 'bundle' is on path."
type bundle

echo "Making sure 'cf' is on path."
type cf