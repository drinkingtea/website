generate:
	hugo
deploy: generate
	rsync -a --delete public/ gary@drinkingtea.net:/data/www
