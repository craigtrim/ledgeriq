install:
	poetry lock
	poetry check
	poetry update
	poetry install

build:
	make install
	poetry build

freeze:
	poetry run pip freeze > requirements.txt
	poetry run python -m pip install --upgrade pip

all:
	make build
	make freeze
