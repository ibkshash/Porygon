# encoding: utf-8

class Twitter
	include Cinch::Plugin

	match /tw(?:itter)? (\S+)/i

	def minutes_in_words(timestamp)
		minutes = (((Time.now - timestamp).abs)/60).round

		return nil if minutes < 0

		case minutes
		when 0..1      then "just now"
		when 2..59     then "#{minutes.to_s} minutes ago"
		when 60..1439        
			words = (minutes/60)
			if words > 1
				"#{words.to_s} hours ago"
			else
				"an hour ago"
			end
		when 1440..11519     
			words = (minutes/1440)
			if words > 1
				"#{words.to_s} days ago"
			else
				"yesterday"
			end
		when 11520..43199    
			words = (minutes/11520)
			if words > 1
				"#{words.to_s} weeks ago"
			else
				"last week"
			end
		when 43200..525599   
			words = (minutes/43200)
			if words > 1
				"#{words.to_s} months ago"
			else
				"last month"
			end
		else                      
			words = (minutes/525600)
			if words > 1
				"#{words.to_s} years ago"
			else
				"last year"
			end
		end
	end

	def prepare_access_token(oauth_token, oauth_token_secret)
		consumer = OAuth::Consumer.new($TWITTER_CONSUMER_KEY, $TWITTER_CONSUMER_SECRET, {:site => "http://api.twitter.com", :scheme => :header })
		token_hash = { :oauth_token => oauth_token, :oauth_token_secret => oauth_token_secret }
		access_token = OAuth::AccessToken.from_hash(consumer, token_hash )

		return access_token
	end


	def execute(m, query)
		return if ignore_nick(m.user.nick)

		begin
			access_token = prepare_access_token($TWITTER_ACCESS_TOKEN, $TWITTER_ACCESS_TOKEN_SECRET)

			response = access_token.request(:get, "https://api.twitter.com/1.1/statuses/user_timeline.json?screen_name=#{query}&count=1&exclude_replies=true")
			parsed_response = JSON.parse(response.body)

			tweettext   = parsed_response[0]["text"].gsub(/\s+/, ' ')
			posted      = parsed_response[0]["created_at"]
			name        = parsed_response[0]["user"]["name"]
			screenname  = parsed_response[0]["user"]["screen_name"]

			urls = parsed_response[0]["entities"]["urls"]

			urls.each do |rep|
				short = rep["url"]
				long  = rep["expanded_url"]
				tweettext = tweettext.gsub(short, long)
			end

			time        = Time.parse(posted)
			time        = minutes_in_words(time)

			tweettext = CGI.unescape_html(tweettext)

			m.reply "Twitter 12| #{name} (@#{screenname}) 12| #{tweettext} 12| Posted #{time}"
		rescue Timeout::Error
			m.reply "Twitter 12| Timeout Error. Maybe twitter is down?"
		rescue
			m.reply "Twitter 12| #{query} 12| Could not get tweet"
		end
	end
end