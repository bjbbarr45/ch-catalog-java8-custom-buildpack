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

echo "Checking for rbenv and Ruby ${p:ruby.version}"
if rbenv version | grep -q "${p:ruby.version}"; then
    echo "Ruby ${p:ruby.version} found"
else
    echo "Ruby ${p:ruby.version} not found"
    exit 1;
fi

echo "Making sure 'ruby' is on path."
type ruby

echo "Checking to see if bundler is installed, any version"
if gem list | grep bundler | grep -q "bundler"; then
    echo "Bundler found"
else
    echo "Bundler not found."
    exit 1
fi

echo "Making sure 'bundle' is on path."
type bundle