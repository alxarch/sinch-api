{exec} = require "child_process"

task "build", "Compile coffee files", ->
	console.log "Compiling coffeescript..."
	exec "coffee -c -b -o lib/ sinch.litcoffee", (err, stdout, stderr) ->
		if err
			console.error err
			process.exit 1
		else
			console.log "OK"
