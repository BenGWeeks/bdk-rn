"""Keep every upstream AAR entry unchanged except the rebuilt native binaries."""
import hashlib
import pathlib
import subprocess
import sys
import tempfile
import zipfile

original, target, destination = map(pathlib.Path, sys.argv[1:])
if hashlib.sha256(original.read_bytes()).hexdigest() != 'b1157894596ab5e792306b305e308ceea14c21d137cf7b7f485415d46833f00f':
    raise ValueError('Unexpected upstream AAR checksum')
abis = {'arm64-v8a': 'aarch64-linux-android', 'x86_64': 'x86_64-linux-android', 'armeabi-v7a': 'armv7-linux-androideabi'}
replacements = {}
for abi, rust_target in abis.items():
    binary = target / rust_target / 'release-smaller/libbdkffi.so'
    headers = subprocess.check_output(['readelf', '-lW', str(binary)], text=True)
    loads = [line.split() for line in headers.splitlines() if line.strip().startswith('LOAD ')]
    if not loads or any(int(load[-1], 16) < 16384 for load in loads):
        raise ValueError(f'{abi} has a load segment below 16 KB alignment')
    for line in headers.splitlines():
        fields = line.split()
        if fields and fields[0] == 'GNU_RELRO' and (int(fields[2], 16) + int(fields[5], 16)) % 16384:
            raise ValueError(f'{abi} has an unaligned RELRO end')
    with zipfile.ZipFile(original) as upstream, tempfile.NamedTemporaryFile() as original_binary:
        original_binary.write(upstream.read(f'jni/{abi}/libbdkffi.so'))
        original_binary.flush()
        def exports(path):
            lines = subprocess.check_output(['nm', '-D', '--defined-only', str(path)], text=True).splitlines()
            return {line.split()[-1] for line in lines if line.split() and line.split()[-1].startswith(('bdk_', 'ffi_'))}
        if exports(original_binary.name) != exports(binary):
            raise ValueError(f'{abi} has changed BDK/UniFFI exported symbols')
    replacements[f'jni/{abi}/libbdkffi.so'] = binary.read_bytes()

destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(original) as source, zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as out:
    for entry in source.infolist():
        contents = replacements.get(entry.filename, source.read(entry.filename))
        info = zipfile.ZipInfo(entry.filename, (1980, 2, 1, 0, 0, 0))
        info.external_attr = entry.external_attr
        info.compress_type = zipfile.ZIP_DEFLATED
        out.writestr(info, contents)
with zipfile.ZipFile(original) as source, zipfile.ZipFile(destination) as rebuilt:
    for name in source.namelist():
        if name not in replacements and source.read(name) != rebuilt.read(name):
            raise ValueError(f'Upstream API/resources changed: {name}')
checksum = hashlib.sha256(destination.read_bytes()).hexdigest()
destination.with_name(destination.name + '.sha256').write_text(f'{checksum}  {destination.name}\n')
print(checksum, destination)
