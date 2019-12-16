#!/bin/bash

base_dir=$PWD
compile_dir="$base_dir"
build_base="$base_dir/vagrant"
build_dir="$build_base/build"
latex_dir="$build_base/build-pdf"
cache_dir="$build_base/pretex-cache"
static_dir="$build_dir/static"
figure_img_dir="$build_dir/figure-images"
pretex="$base_dir/gt-text-common/pretex/pretex.py"
node_dir="$build_base/node_modules"

# Run in the vagrant build vm
if [ ! -d "$base_dir" ]; then
    if [ ! $(vagrant status --machine-readable | grep state,running) ]; then
        vagrant up || die "Cannot start build environment virtual machine"
    fi
    vagrant ssh -- "$compile_dir/build.sh" "$@"
    exit $?
fi


die() {
    echo "$@"
    exit 1
}

compile_latex() {
    (cd "$latex_dir" && \
            TEXINPUTS=".:$latex_dir/style:" pdflatex \
                     -interaction=nonstopmode "\input{index}" \
                || die "pdflatex failed")
}

make_hashes() {
    cat >xsl/git-hash.xsl <<EOF
<?xml version='1.0'?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"
    xmlns:exsl="http://exslt.org/common"
    extension-element-prefixes="exsl">
  <xsl:template name="git-hash">
    <xsl:text>$(git rev-parse HEAD)</xsl:text>
  </xsl:template>
  <xsl:template name="git-hash-short">
    <xsl:text>$(git rev-parse HEAD | cut -c 1-6)</xsl:text>
  </xsl:template>
  <xsl:template name="versioned-file">
    <xsl:param name="file"/>
    <xsl:variable name="commit">
      <xsl:choose>
        <xsl:when test="\$file='static/gt-linalg.js'">
          <xsl:text>$(git hash-object "$build_dir"/static/gt-linalg.js | cut -c 1-6)</xsl:text>
        </xsl:when>
        <xsl:when test="\$file='static/gt-linalg.css'">
          <xsl:text>$(git hash-object "$build_dir"/static/gt-linalg.css | cut -c 1-6)</xsl:text>
        </xsl:when>
        <xsl:when test="\$file='demos/cover.js'">
          <xsl:text>$(git hash-object "$build_dir"/demos/cover.js | cut -c 1-6)</xsl:text>
        </xsl:when>
      </xsl:choose>
    </xsl:variable>
    <xsl:value-of select="\$file"/>
    <xsl:text>?vers=</xsl:text>
    <xsl:value-of select="\$commit"/>
  </xsl:template>
</xsl:stylesheet>
EOF
}

combine_css() {
    if [ -n "$MINIFY" ]; then
        "$node_dir"/clean-css-cli/bin/cleancss --skip-rebase "$@"
    else
        cat "$@"
    fi
}

combine_js() {
    if [ -n "$MINIFY" ]; then
        "$node_dir"/uglify-js/bin/uglifyjs -m -- "$@"
    else
        (
            for file in "$@"; do
                cat "$file"
                echo ";"
            done
        )
    fi
}


VERSION=default
PRETEX_ALL=
LATEX_TOO=
MINIFY=
DEMOS=
CHUNKSIZE="250"

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            shift
            VERSION=$1
            ;;
        --reprocess-latex)
            PRETEX_ALL="true"
            ;;
        --pdf-vers)
            LATEX_TOO="true"
            ;;
        --minify)
            MINIFY="true"
            ;;
        --demos)
            DEMOS="true"
            ;;
        --chunk)
            shift
            CHUNKSIZE=$1
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
    shift
done

if [ -n "$DEMOS" ]; then
    echo "Generating demos..."
    "$compile_dir/demos/generate.py" \
        || die "Can't generate demos"
fi

echo "Preprocessing "
XML_FILE="$build_base/$VERSION.xml"
if [ $VERSION == "default" ]; then
    PDF_FILE="ila.pdf"
else
    PDF_FILE="ila-$VERSION.pdf"
fi
cd "$compile_dir"
xsltproc -o "$XML_FILE" --xinclude --stringparam version $VERSION \
         xsl/versioning.xsl linalg.xml

echo "Checking xml..."
xmllint --xinclude --noout --relaxng "$base_dir/mathbook/schema/pretext.rng" \
        "$XML_FILE"
if [[ $? == 3 || $? == 4 ]]; then
    echo "Input is not valid MathBook XML; exiting"
    exit 1
fi


echo "Cleaning up previous build..."
rm -rf "$build_dir"
mkdir -p "$build_dir"
mkdir -p "$static_dir"
mkdir -p "$static_dir/fonts"
mkdir -p "$static_dir/images"

if [ -n "$LATEX_TOO" ]; then
    echo "***************************************************************************"
    echo "BUILDING PDF"
    echo "***************************************************************************"
    rm -rf "$latex_dir"
    mkdir -p "$latex_dir"
    cp -r "$compile_dir/style" "$latex_dir/style"
    cp -r "$compile_dir/figure-images" "$latex_dir/figure-images"
    mkdir -p "$latex_dir/static"
    cp -r "$compile_dir/images" "$latex_dir/static/images"
    echo "Generating master LaTeX file"
    xsltproc -o "$latex_dir/" --xinclude \
             "$compile_dir/xsl/mathbook-latex.xsl" "$XML_FILE" \
        || die "xsltproc failed!"
    echo "Compiling PDF version (pass 1)"
    compile_latex
    echo "Compiling PDF version (pass 2)"
    compile_latex
    mv "$latex_dir"/index.pdf "$build_dir/$PDF_FILE"
fi

echo "***************************************************************************"
echo "BUILDING HTML"
echo "***************************************************************************"

echo "Copying static files..."
combine_css "$base_dir/mathbook-assets/stylesheets/mathbook-gt.css" \
            "$base_dir/mathbook/css/mathbook-add-on.css" \
            "$base_dir/gt-text-common/css/mathbook-gt-add-on.css" \
            "$base_dir/gt-text-common/css/knowlstyle.css" \
            "$compile_dir/demos/mathbox/mathbox.css" \
            > "$static_dir/gt-linalg.css"
combine_js "$base_dir/gt-text-common/js/jquery.min.js" \
           "$base_dir/gt-text-common/js/jquery.sticky.js" \
           "$base_dir/gt-text-common/js/knowl.js" \
           "$base_dir/gt-text-common/js/GTMathbook.js" \
           > "$static_dir/gt-linalg.js"

cp "$base_dir/mathbook-assets/stylesheets/fonts/ionicons/fonts/"* "$static_dir/fonts"
cp -r "$base_dir/gt-text-common/fonts/"* "$static_dir/fonts"
cp "$compile_dir/images/"* "$static_dir/images"
cp "$compile_dir/manifest.json" "$build_dir"
cp "$compile_dir/extra/google9ccfcae89045309c.html" "$build_dir"

cp -r "$compile_dir/build-demos" "$build_dir/demos"
if [ -n "$MINIFY" ]; then
    for js in "$build_dir/demos/"*.js "$build_dir/demos/"*/*.js; do
        "$node_dir"/uglify-js/bin/uglifyjs -m -- "$js" > "$js".min
        mv "$js".min "$js"
    done
    for css in "$build_dir/demos/css/"*.css; do
        "$node_dir"/clean-css-cli/bin/cleancss --skip-rebase "$css" > "$css".min
        mv "$css".min "$css"
    done
fi

echo "Converting xml to html..."
make_hashes
xsltproc -o "$build_dir/" --xinclude --stringparam pdf.online $PDF_FILE \
         "$compile_dir/xsl/mathbook-html.xsl" "$XML_FILE" \
    || die "xsltproc failed!"

echo "Preprocessing LaTeX (be patient)..."
[ -n "$PRETEX_ALL" ] && rm -r "$cache_dir"
python3 "$pretex" --chunk-size $CHUNKSIZE --preamble "$build_dir/preamble.tex" \
        --cache-dir "$cache_dir" --style-path "$compile_dir/style" \
        --build-dir "$build_dir" \
    || die "Can't process html!"
mkdir "$figure_img_dir"
cp "$cache_dir"/*.png "$figure_img_dir"

echo "Cleaning up..."
cp "$build_dir"/index2.html "$build_dir"/index.html
rm "$build_dir"/preamble.tex

echo "Build successful!  Open or reload"
echo "     http://localhost:8081/"
echo "in your browser to see the result."
