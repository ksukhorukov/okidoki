#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'eventmachine'
require 'em-websocket'
require 'sinatra/base'
require 'mongo'
require 'thin'
require 'json'

include Mongo


def run(opts)

  
  EM.run do

    
    server  = opts[:server] || 'thin'
    host    = opts[:host]   || '0.0.0.0'
    port    = opts[:port]   || '8181'
    web_app = opts[:app]

    dispatch = Rack::Builder.app do
      map '/' do
        run web_app
      end
    end

    
    unless ['thin', 'hatetepe', 'goliath'].include? server
      raise "Need an EM webserver, but #{server} isn't"
    end

    Rack::Server.start({
      app:    dispatch,
      server: server,
      Host:   host,
      Port:   port
    })

    clients = Hash.new()
    documents = Hash.new() 

    conn = MongoClient.new('localhost', 27017)
    mongo_db = conn.db('okidoki')
    coll = mongo_db['docs']   


    EM::WebSocket.start(:host => '0.0.0.0', :port => 8182) do |websocket|
     EM.defer do 
       websocket.onopen {   puts "Client connected"  }

       websocket.onmessage do |msg|
          
          metadata = JSON.parse(msg)

          doc_id = metadata['doc_id']; 
          user_id = metadata['user_id'];
          user_name = metadata['user_name'];


          timestamp = Time.now.to_i

          if metadata['msg_type'].eql?('init')

              puts "Initialization of new client..."

              if documents.has_key?(doc_id) 

                 content = documents[doc_id]['content']

              else

                 documents[doc_id] = Hash.new
                 documents[doc_id]['editors'] = Hash.new

                 
                 puts "On the 'EM' side we have no data assosiated with doc_#{doc_id}. Will try to get something from Mongo."
                 doc = coll.find({ "_id" => BSON::ObjectId(doc_id)}).to_a
                 puts "Greped from mongo: #{doc}"

                 unless doc.empty?

    	            documents[doc_id]['content'] = doc.first['content'].to_s
		    puts "Data loaded from Mongo: #{content}"

                 else 

                    puts "We have a new document. ID: #{doc_id}"
                    documents[doc_id]['content'] = ''
                    
                 end
                 

              end

              documents[doc_id]['editors'][user_id] = true
              documents[doc_id]['timestamp'] = timestamp

              puts "next_step_1"
              

              puts "Sending current state of content to the new client: #{documents[doc_id]['content']}"
              websocket.send({msg_type: "update", body: documents[doc_id]['content']}.to_json) 
                      
              puts "Fill in socket information..."
             
              clients[user_id] = Hash.new
              clients[user_id]['user_name'] = user_name 
              clients[user_id]['websocket'] = websocket
              clients[user_id]['doc_id'] = doc_id

              puts "We have a new client. ID: #{user_id} - #{user_name}. Metadata: #{clients[user_id]}"              
              puts "Need to propogate changed list of editors"

              editors_user_names = Array.new
              documents[doc_id]['editors'].keys.each { |editor_id| editors_user_names.push(clients[editor_id]['user_name']) }       
              puts "Editors of #{doc_id}: #{editors_user_names}"      
              documents[doc_id]['editors'].keys.each { |editor_id|
                   
                 clients[editor_id]['websocket'].send( { msg_type: "editors_list", body: editors_user_names }.to_json )

              }              
           
          elsif metadata['msg_type'].eql?('update')

             content = metadata['content'];
          
          
             if timestamp < documents[doc_id]['timestamp']
                puts "Collision detected. Tried to update #{doc_id} that have timestamp: #{documents[doc_id]['timestamp']} with meta that have timestamp: #{metadata['timestamp']}"
             else 
                documents[doc_id]['content'] = content
                documents[doc_id]['timestamp'] = timestamp
                puts "Document (id = #{doc_id}) updated: #{documents[doc_id]['content']}"
                puts "Connected clients: #{documents[doc_id]['editors'].keys}"
             end

              # and now we have to propogate all changes in documents through all websockets assosiated with user identifactors assosiated with this document
             puts "Current state of doc ID #{doc_id}: #{documents[doc_id]['content']}"
             documents[doc_id]['editors'].keys.each { |user_id|
                puts "Propogating changes to: #{user_id} - #{clients[user_id]['user_name']}"
                clients[user_id]['websocket'].send({msg_type: "update", body: documents[doc_id]['content']}.to_json) 
             }
      
         end
        end
       end

        websocket.onclose { 
         EM.defer do 
  
          puts "Client disconnected"

          clients.keys.each { |user_id|

             puts "Inspecting webscoket of #{user_id}:"
             puts "+=================================================+"
             puts clients[user_id]['websocket']
             puts "+=================================================+"

             if clients[user_id]['websocket'] === websocket
                puts "Match found! Prepearing to delete."
                doc_id = clients[user_id]['doc_id']
                documents[doc_id]['editors'].delete(user_id)
                editors_user_names = Array.new
                documents[doc_id]['editors'].keys.each { |editor_id| editors_user_names.push(clients[editor_id]['user_name']) }
                puts "Editors list for doc id #{doc_id} has been changed recently. Propogating changes."
                documents[doc_id]['editors'].keys.each { |editor_id|              
                   clients[editor_id]['websocket'].send( { msg_type: "editors_list", body: editors_user_names }.to_json )
                }

                clients.delete(user_id)      
                number_of_editors = documents[doc_id]['editors'].keys.count  
  
                if(number_of_editors == 0)
                   puts "Saving doc_#{doc_id} content to Mongo"
                   coll.update( { "_id" => BSON::ObjectId(doc_id) }, { "$set" => { :content => documents[doc_id]['content'] } } )
                   puts "Content: #{documents[doc_id]['content']} saved."
                   documents.delete(doc_id)
                   puts "Document #{doc_id} temporary data deleted from EM storage"
                end 
                break        
             end
         }
         end
       }

      websocket.onerror { |e| puts "err #{e.inspect}" }

    end

  end

end


class OkiDoki < Sinatra::Base

configure do

    conn = MongoClient.new('localhost', 27017)
    set :mongo_connection, conn
    set :mongo_db, conn.db('okidoki')
    set :coll, mongo_db['docs']    
    set :threaded, false
    enable :sessions

  end
  


  get '/' do
          
    create_session_if_not_exists()

    docs_count =  settings.coll.count.to_i
    docs = settings.coll.find.to_a

    erb :index, :locals => { :docs_count => docs_count, :docs => docs }

  end
 

  get '/edit' do
    create_session_if_not_exists() 
    erb :new_document
  end

  get '/set_name/?:name' do

      count = settings.coll.find({ "doc_name" => params[:name]}).to_a.count;

      if count > 0
         {:success => "false", :description => "This document name is already in use", :count => count}.to_json
      else
         doc_id = settings.coll.insert("user_id" => session['user_id'] , "user_name" => session['user_name'], "content" => "", "doc_name" => params[:name])
         session[:doc_id] = doc_id.to_s              
         session[:doc_name] = params[:name]
         {:success => "true", :description => params[:name]}.to_json 
         #settings.coll.find({ "_id" => BSON::ObjectId(session[:doc_id])}).to_a.to_json
      end
     
  end
 
  get '/edit/:doc_name' do

    doc = settings.coll.find("doc_name" => params[:doc_name]).to_a;
    
    if(doc.empty?) 
       error = "Incorrect document name"
       erb :error, :locals => { :error => error }
    else 
      create_session_if_not_exists()
      session[:doc_id] = doc.first["_id"].to_s
      session[:doc_name] = doc.first["doc_name"].to_s
      erb :edit 
    end

  end

  get '*' do
     redirect '/'
  end

  helpers do

     def create_session_if_not_exists
       if (session[:user_id].nil? or session[:user_name].nil?)
          session[:user_id] = (rand() * 10000).to_i.to_s
          session[:user_name] = "user_" + session[:user_id] 
       end
     end

  end

end


run app: OkiDoki.new
