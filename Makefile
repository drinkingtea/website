generate:
	hugo
deploy: generate
	rsync -a --delete public/ root@drinkingtea.net:/srv/persistence/drinkingtea.net/web/drinkingtea.net/public
