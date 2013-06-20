okidoki
======= 


http://github.com/ksukhorukov/okidoki

<b>== DESCRIPTION:</b>

'OkiDoki' is an extremely light and fast collaboration platform created mostly for fun and educational purposes. 
Multiple users can create/edit documents in real-time mode and perform this operations almost instantly. 

Technology stack: Ruby, Sinatra, Thin, EventMachine and MongoDB.

<b>== REQUIREMENTS</b>

1) Ruby v.1.9.3 or higher<br/>
2) gems from the 'Gemfile' & all dependences

NOTE: Run your mongodb service without credentials for the localhost (this is so by default).


<b>== INSTALLATION</b>


$ gem install bundler<br/>
$ bundle install

<b>== RUN</b>


okidoki$ ./server.rb 
>> Thin web server (v1.5.1 codename Straight Razor)
>> Maximum connections set to 1024
>> Listening on 0.0.0.0:8181, CTRL+C to stop
...

Then go to http://127.0.0.1:8181 and have fun.
