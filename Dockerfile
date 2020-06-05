FROM lambci/lambda:build-python3.6

COPY ./requirements.txt /tmp/requirements.txt
COPY ./numpy-github-issue-13248.patch /tmp
RUN yum -y update && yum -y install \
    gcc-gfortran python3-devel openblas openblas-devel lapack lapack-devel && \
    mkdir -p /build/{lib,python} && \
    find /usr -name libopenblasp64.so -exec cp {} /build/lib \; && \
    find /usr -name liblapack.so.3  -exec cp {} /build/lib \; && \
    yum -y remove gcc-gfortran python3-devel openblas openblas-devel lapack lapack-devel && \
    yum -y autoremove && \
    ls /build/lib && \
    ln -s /build/lib /opt/lib

RUN pip install pytest

# Use "--no-compile" here because "--compile" generates suboptimal .pyc files in __pycache__ folders.
RUN CFLAGS="-g0 -Os -Wl,--strip-all -I/usr/include:/usr/local/include -L/usr/lib:/usr/local/lib" && \ 
    pip install \
    --no-cache-dir \
    --no-compile \ 
    --global-option=build_ext \
    --global-option="-j 3" \
    -r /tmp/requirements.txt \
    -t /build/python

WORKDIR /build

# Patch bug in numpy (before compilation to .pyc) to allow doc removal
# github.com/numpy/numpy/issues/13248
RUN patch python/numpy/core/overrides.py /tmp/numpy-github-issue-13248.patch

RUN printf "Size after installation:\n" > /tmp/size-delta.txt && \
    du -h --max-depth=2 >> /tmp/size-delta.txt

RUN cp -r /build/python /tmp && \
    cd /tmp/python && \
    python -c 'import numpy; numpy.test("full");'

# Generate pyc files, use "-b" to write the byte-code files to their legacy
# locations and names to allow removal of the original .py source files.
# Use "-OO" to remove assert statements, code conditional on __debug__, discard docstrings.
# docs.python.org/3/using/cmdline.html#cmdoption-oo
# docs.python.org/3/library/compileall.html#cmdoption-compileall-b
RUN python -OO -m compileall -q -b ./python

RUN printf "Size after compilation:\n" >> /tmp/size-delta.txt && \
    du -h --max-depth=2 >> /tmp/size-delta.txt

# Strip .so files, delete .py files and -info, doc, tests folders.
RUN find . -type f -name "*.so" -exec strip --strip-all {} + && \
    find . -type f -name "*.py" -exec rm {} + && \
    find . -type d -name "*-info" -exec rm -rf {} + && \
    find . -type d -name doc -exec rm -rf {} + && \
    find . -type d -name tests -exec rm -rf {} + 

# TODO fix duplicates in numpy.libs and scipy/.libs

RUN printf "Size after removing docs, tests, *.py files, *.-info folders and stripping *.so files:\n" >> /tmp/size-delta.txt && \
    du -h --max-depth=2 >> /tmp/size-delta.txt
RUN cat /tmp/size-delta.txt

RUN zip -r9q /tmp/layer.zip /build
RUN du -sh /tmp/layer.zip
