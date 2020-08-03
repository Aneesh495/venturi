from setuptools import setup, find_packages

setup(
    name="venturi-sdk",
    version="1.0.0",
    description="Python Client SDK and Bitstream Validation Harness for Venturi Streaming Engine",
    author="Aneesh Krishna",
    packages=find_packages(),
    python_requires=">=3.8",
    classifiers=[
        "Programming Language :: Python :: 3",
        "Topic :: Multimedia :: Video",
        "Topic :: Internet :: WWW/HTTP",
    ],
)
