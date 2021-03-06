# encoding: utf-8

Encoding.default_external = "UTF-8"
Encoding.default_internal = "UTF-8"

class Uri 
	include Cinch::Plugin

	# Human readable timestamp for Twitter URLs
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

	def length_in_minutes(seconds=0)
		seconds = Duration.new(seconds).to_i

		if seconds > 3599
			length = [seconds/3600, seconds/60 % 60, seconds % 60].map{|t| t.to_s.rjust(2,'0')}.join(':')
		elsif seconds > 59
			length = [seconds/60 % 60, seconds % 60].map{|t| t.to_s.rjust(2,'0')}.join(':')
		else
			length = "00:#{seconds.to_s.rjust(2,'0')}"
		end

		return length
	end

	def add_commas(digits)
		digits.nil? ? 0 : digits.reverse.gsub(%r{([0-9]{3}(?=([0-9])))}, "\\1,").reverse
	end

	def prepare_access_token(oauth_token, oauth_token_secret)
		consumer = OAuth::Consumer.new($TWITTER_CONSUMER_KEY, $TWITTER_CONSUMER_SECRET, {:site => "http://api.twitter.com", :scheme => :header })
		token_hash = { :oauth_token => oauth_token, :oauth_token_secret => oauth_token_secret }
		access_token = OAuth::AccessToken.from_hash(consumer, token_hash )

		return access_token
	end


	listen_to :channel # Only react in a channel
	def listen(m)
		URI.extract(m.message, ["http", "https"]).first(1).each do |link|
			return if ignore_nick(m.user.nick) or uri_disabled(m.channel.name)

			uri = URI.parse(link)

			begin

				if(@agent.nil?)
					@agent = Mechanize.new { |agent|
						agent.user_agent_alias    = "Windows Mozilla"
						agent.follow_meta_refresh = false
						agent.redirect_ok         = true
						agent.verify_mode         = OpenSSL::SSL::VERIFY_NONE
						agent.keep_alive          = false
						agent.open_timeout        = 10
						agent.read_timeout        = 10
					}
				end

				if uri.host == "t.co"
					final_uri = ''
					open(link) { |h| final_uri = h.base_uri }

					link = final_uri.to_s
					uri = URI.parse(final_uri.to_s)
				end

				m.reply get_info(m, link)

			rescue Mechanize::ResponseCodeError => ex
				m.reply "Title 03|\u000F #{ex.response_code} Error 03|\u000F #{uri.host}" 
			rescue
				nil
			end
		end
	end

	def get_info(m, link)
		begin
			uri = URI.parse(link)
			http = Net::HTTP.new(uri.host, uri.port)

			if link.start_with?("https")
				http.verify_mode = OpenSSL::SSL::VERIFY_NONE
				http.use_ssl = true						
			end

			http.open_timeout = 6 # in seconds
			http.read_timeout = 6 # in seconds

			request = Net::HTTP::Head.new(uri.request_uri)
			request.initialize_http_header({"User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.10; rv:35.0) Gecko/20100101 Firefox/35.0"})

			get_response(m, http.request(request), link, uri)
		rescue
			nil
		end
	end

	def get_response(m, response, link, uri)
		if response["location"]
			get_info(m, response["location"])
		else
			print_info(m, response, link, uri)
		end
	end

	def print_info(m ,response, link, uri)

		# Title
		if response["content-type"].to_s.include? "text/html" and response.code != "400"

			case uri.host

			when "boards.4chan.org"
				link_4chan(m, link, uri)

			when "8ch.net"
				link_8chan(m, link, uri)

			when "twitter.com"
				link_twitter(m, link, uri)

			when "www.youtube.com"
				link_youtube(m, link, false)

			when "youtu.be"
				link_youtube(m, link, true)

			else # Generic Title
				link_generic(m, link)

			end

		# File
		elsif response.code != "400"
			return if file_info_disabled(m.channel.name)

			fileSize = response['content-length'].to_i

			case fileSize
				when 0..1024 then size = (fileSize.round(1)).to_s + " B"
				when 1025..1048576 then size = ((fileSize/1024.0).round(1)).to_s + " KB"
				when 1048577..1073741824 then size = ((fileSize/1024.0/1024.0).round(1)).to_s + " MB"
				else size = ((fileSize/1024.0/1024.0/1024.0).round(1)).to_s + " GB"
			end

			filename = ''

			if response['content-disposition']
				filename = response['content-disposition'].gsub("inline;", "").gsub("filename=", "").gsub(/\s+/, ' ') + " "
			end

			type = response['content-type']

			"File 03|\u000F %s%s %s 03|\u000F %s" % [filename, type, size, uri.host]
		end

	end


	def link_4chan(m, link, uri)

		doc = @agent.get(link)
		bang = URI::split(link.gsub('#reply', ''))

		if bang[5].include? "/thread/"

			if bang[8] != nil
				postnumber = bang[8].gsub('p', '')
			else
				postnumber = bang[5].scan(/thread\/(\d+)/).first.last
			end

			subject   = doc.search("//div[@id='pi#{postnumber}']//span[@class='subject']").text
			poster    = doc.search("//div[@id='pi#{postnumber}']//span[@class='name']").text
			capcode   = doc.search("//div[@id='pi#{postnumber}']//strong[contains(@class,'capcode')]").text
			flag      = doc.search("//div[@id='pi#{postnumber}']//span[contains(concat(' ',normalize-space(@class),' '),' flag ')]/@title").text # http://pivotallabs.com/xpath-css-class-matching/
			trip      = doc.search("//div[@id='pi#{postnumber}']//span[@class='postertrip']").text
			reply     = doc.search("//div[@id='p#{postnumber}']/blockquote").inner_html.gsub("<br>", " ").gsub("<span class=\"quote\">", "03").gsub("<s>", "01,01").gsub(/<\/s\w*>/, "\u000F")
			reply     = reply.gsub(/<\/?[^>]*>/, "").gsub("&gt;", ">")
			image     = doc.search("//div[@id='f#{postnumber}']/a[1]/@href").text
			date      = doc.search("//div[@id='p#{postnumber}']//span[@class='dateTime']/@data-utc").text

			date = Time.at(date.to_i)
			date = minutes_in_words(date)

			subject = subject+" " if subject != ""
			reply = " 03|\u000F "+reply if reply != ""
			reply = reply[0..160]+" ..." if reply.length > 160
			image = " 03|\u000F File: https:"+image if image.length > 1
			flag = flag+" " if flag.length > 1
			capcode = " "+capcode if capcode.length > 1

			"4chan 03|\u000F %s03%s%s%s\u000F %s(%s) No.%s%s%s" % [subject, poster, trip, capcode, flag, date, postnumber, image, reply]

		else # Board Index Title
			link_generic(m, link)
		end
	end

	def link_8chan(m, link, uri)

		doc = @agent.get(link)
		bang = URI::split(link)

		if bang[5].include? "/res/"

			if bang[8] != nil
				postnumber = bang[8]

				subject   = doc.search("//div[@id='reply_#{postnumber}']/p[@class='intro']//span[@class='subject']").text
				poster    = doc.search("//div[@id='reply_#{postnumber}']/p[@class='intro']//span[@class='name']").text
				trip      = doc.search("//div[@id='reply_#{postnumber}']/p[@class='intro']//span[@class='trip']").text
				capcode   = doc.search("//div[@id='reply_#{postnumber}']/p[@class='intro']//span[@class='capcode']").text
				flag      = doc.search("//div[@id='reply_#{postnumber}']/p[@class='intro']//img[contains(concat(' ',normalize-space(@class),' '),' flag ')]/@title").text

				reply     = doc.search("//div[@id='reply_#{postnumber}']/div[@class='body']").inner_html.gsub("<br>", " ").gsub("<span class=\"quote\">", "03").gsub("<s>", "01,01").gsub(/<\/s\w*>/, "\u000F")
				reply     = reply.gsub(/<\/?[^>]*>/, "").gsub("&gt;", ">")
				image     = doc.search("//div[@id='reply_#{postnumber}']/div[@class='files']/div[@class='file']/p[@class='fileinfo']/a[1]/@href").text
				date      = doc.search("//div[@id='reply_#{postnumber}']/p[@class='intro']//time/@datetime").text
			else
				postnumber = bang[5].scan(/res\/(\d+)/).first.last

				
				subject   = doc.search("//div[@class='post op']/p[@class='intro']//span[@class='subject']").text
				poster    = doc.search("//div[@class='post op']/p[@class='intro']//span[@class='name']").text
				trip      = doc.search("//div[@class='post op']/p[@class='intro']//span[@class='trip']").text
				capcode   = doc.search("//div[@class='post op']/p[@class='intro']//span[@class='capcode']").text
				flag      = doc.search("//div[@class='post op']/p[@class='intro']//img[contains(concat(' ',normalize-space(@class),' '),' flag ')]/@title").text
				date      = doc.search("//div[@class='post op']/p[@class='intro']//time/@datetime").text

				reply     = doc.search("//div[@class='post op']/div[@class='body']").inner_html.gsub("<br>", " ").gsub("<span class=\"quote\">", "03").gsub("<s>", "01,01").gsub(/<\/s\w*>/, "\u000F")
				reply     = reply.gsub(/<\/?[^>]*>/, "").gsub("&gt;", ">")
				image     = doc.search("//div[@id='thread_#{postnumber}']/div[@class='files']/div[@class='file']/p[@class='fileinfo']/a[1]/@href").text
			end

			date = Time.parse(date)
			date = minutes_in_words(date)

			subject = subject+" " if subject != ""
			reply = " 03|\u000F "+reply if reply != ""
			reply = reply[0..160]+" ..." if reply.length > 160
			image = " 03|\u000F File: "+image if image.length > 1
			flag = flag+" " if flag.length > 1
			capcode = " "+capcode if capcode.length > 1

			"\u221Echan 03|\u000F %s03%s%s%s\u000F %s(%s) No.%s%s%s" % [subject, poster, trip, capcode, flag, date, postnumber, image, reply]

		else # Board Index Title
			link_generic(m, link)
		end
	end

	def link_twitter(m, link, uri)
		bang = link.split("/")
		begin
			if bang[4].include? "status"
				access_token = prepare_access_token($TWITTER_ACCESS_TOKEN, $TWITTER_ACCESS_TOKEN_SECRET)

				response = access_token.request(:get, "https://api.twitter.com/1.1/statuses/show/#{bang[5]}.json")
				parsed_response = JSON.parse(response.body)

				tweettext   = parsed_response["text"].gsub(/\s+/, ' ')
				posted      = parsed_response["created_at"]
				name        = parsed_response["user"]["name"]
				screenname  = parsed_response["user"]["screen_name"]

				urls = parsed_response["entities"]["urls"]

				urls.each do |rep|
					short = rep["url"]
					long  = rep["expanded_url"]
					tweettext = tweettext.gsub(short, long)
				end

				if parsed_response["entities"].has_key?("media")
					media = parsed_response["extended_entities"]["media"][0]

					if (media["type"] == "animated_gif" or media["type"] == "video")
						image_url = media["video_info"]["variants"][0]["url"]
						image_url = shorten_url(image_url)
					else
						image_url = media["media_url_https"]
						image_url = shorten_url(image_url + ":orig")
					end

					image_tco = media["url"]
					tweettext = tweettext.gsub(image_tco, image_url)
				end

				time        = Time.parse(posted)
				time        = minutes_in_words(time)

				tweettext = CGI.unescape_html(tweettext)

				"Twitter 12|\u000F #{name}\u000F (@#{screenname}) 12|\u000F #{tweettext} 12|\u000F Posted #{time}"
			else
				link_generic(m, link)
			end
		rescue
			link_generic(m, link)
		end
	end



	def link_youtube(m, link, short)
		begin
			if short == true
				id = URI.parse(link).path.gsub("/", "")
			else 
				foo = CGI.parse(URI.parse(link).query)
				id = foo["v"][0]
			end
			
			url      = open("https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,statistics&id=#{id}&key=#{$YOUTUBE_API}").read
			hashed   = JSON.parse(url)

			name     = hashed["items"][0]["snippet"]["title"]
			views    = hashed["items"][0]["statistics"]["viewCount"] || 0
			likes    = hashed["items"][0]["statistics"]["likeCount"] || 0
			dislikes = hashed["items"][0]["statistics"]["dislikeCount"] || 0
			length   = hashed["items"][0]["contentDetails"]["duration"] || "PT1M1S"

			views    = add_commas(views) 
			votes    = likes.to_i + dislikes.to_i
			rating   = (votes > 0 ? (((likes.to_i+0.0)/votes.to_i)*100) : 0.0)
			rating   = rating.round.to_s + "%"
			length   = length_in_minutes(length)

			"YouTube 05|\u000F %s 05|\u000F %s 05|\u000F %s views 05|\u000F %s" % [name[0..140], length, views, rating]
		rescue
			link_generic(m, link)
		end
	end



	def link_generic(m, link)
		page  = @agent.get(link)
		
		if page.at('meta[property="og:title"]') and page.search('meta[property="og:title"]')[0]["content"].length > 0
			title = page.search('meta[property="og:title"]')[0]["content"].gsub(/\s+/, ' ').strip
		elsif page.at('meta[property="title"]') and page.search('meta[property="title"]')[0]["content"].length > 0
			title = page.search('meta[property="title"]')[0]["content"].gsub(/\s+/, ' ').strip
		else
			title = page.title.gsub(/\s+/, ' ').strip
		end

		uri = URI.parse(page.uri.to_s)
		"Title 03|\u000F %s 03|\u000F %s" % [title[0..140], uri.host]
	end

#Class dismissed
end