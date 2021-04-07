require 'line/bot'

class NakanoController < ApplicationController
	protect_from_forgery with: :null_session

	def webhook

		# 紀錄頻道
		Channel.find_or_create_by(channel_id: channel_id)

		# 教話
		reply_learn_text = learn(channel_id, received_text)

		# 忘話
		reply_forget_text = forget(channel_id, received_text)

		# 關鍵字回覆
		reply_text = keyword_reply(channel_id, received_text) if reply_text.nil?

		# 教圖片
		reply_learn_image_text = learn_image(received_text)

		# 關鍵字圖片回覆
		reply_image = image_keyword_reply(received_text) if reply_image.nil?

		# 推齊
		reply_text = echo2(channel_id, received_text) if reply_text.nil?

		# 記錄對話
		save_to_received(channel_id, received_text)
		save_to_reply(channel_id, reply_text)

		# 傳送訊息到 line
		response = reply_text_to_line(reply_text)

		# 傳送 learn 訊息到 line
		response = reply_learn(reply_learn_text)

		# 傳送 forget 訊息到 line
		response = reply_forget(reply_forget_text)

		# 傳送圖片到 line
		response = reply_image_to_line(reply_image)

		# 傳送 教圖片 訊息到 line
		response = reply_learn_image(reply_learn_image_text)

		# 回應 200
		head :ok
	end

	# 頻道 ID
	def channel_id
		source = params['events'][0]['source']
		source['groupId'] || source['roomId'] || source['userId']
	end

	# 儲存對話
	def save_to_received(channel_id, received_text)
		return if received_text.nil?
		Received.create(channel_id: channel_id, text: received_text)
	end

	# 儲存回應
	def save_to_reply(channel_id, reply_text)
		return if reply_text.nil?
		Reply.create(channel_id: channel_id, text: reply_text)
	end

	# 推齊
	def echo2(channel_id, received_text)
		# 如果在 channel_id 最近沒人講過 received_text，三玖就不回應
		recent_received_texts = Received.where(channel_id: channel_id).last(1)&.pluck(:text)
		return nil unless received_text.in? recent_received_texts

		# 如果在 channel_id 三玖上一句回應是 received_text，三玖就不回應
		last_reply_text = Reply.where(channel_id: channel_id).last&.text
		return nil if last_reply_text == received_text

		received_text
	end

	 # 取得對方說的話
	def received_text
		message = params['events'][0]['message']
		message['text'] unless message.nil?
	end

	# 教話
	def learn(channel_id, received_text)
		#如果開頭不是 39l 就跳出
		return nil unless received_text[0..2] == '39l'

		received_text = received_text[3..-1]
		semicolon_index = received_text.index('$')

		# 找不到 $ 就跳出
		return nil if semicolon_index.nil?

		keyword = received_text[0..semicolon_index-1]
		message = received_text[semicolon_index+1..-1]

		KeywordMapping.create(channel_id: channel_id, keyword: keyword, message: message)

		'記起來了~'
	end

	# 忘話
	def forget(channel_id, received_text)
		# 如果開頭不是 39f 就跳出
		return nil unless received_text[0..2] == '39f'

		received_text = received_text[3..-1]
		semicolon_index = received_text.index('%')

		# 找不到 % 就跳出
		return nil if semicolon_index.nil?

		keyword = received_text[0..semicolon_index-1]
		message = received_text[semicolon_index+1..-1]

		KeywordMapping.where(channel_id: channel_id, keyword: keyword, message: message).destroy_all

		'我忘記了...'
	end

	# 教圖片
	def learn_image(received_text)
		# 如果開頭不是 39li 就跳出
		return nil unless received_text[0..3] == '39li'

		received_text = received_text[4..-1]
		semicolon_index = received_text.index('$')

		# 找不到 % 就跳出
		return nil if semicolon_index.nil?

		keyword = received_text[0..semicolon_index-1]
		image = received_text[semicolon_index+1..-1]

		ImageKeywordMapping.create(keyword: keyword, image: image)

		'這圖片真有趣呢~'
	end

	# 關鍵字回覆
	def keyword_reply(channel_id, received_text)
		message = KeywordMapping.where(channel_id: channel_id, keyword: received_text).order("random()").first&.message
		return message unless message.nil?
	end

	# 關鍵字圖片回覆
	def image_keyword_reply(received_text)
		ImageKeywordMapping.where(keyword: received_text).order("random()").first&.image
	end

	# 傳送訊息到 line
	def reply_text_to_line(reply_text)
		return nil if reply_text.nil?

		# 取得 reply token
		reply_token = params['events'][0]['replyToken']

		# 設定回覆訊息
		message = {
			type: 'text',
			text: reply_text
		}

		# 傳送訊息
		line.reply_message(reply_token, message)
	end

	# 傳送 learn 訊息到 line
	def reply_learn(reply_learn_text)
		return nil if reply_learn_text.nil?

		# 取得 reply token
		reply_token = params['events'][0]['replyToken']

		# 設定回覆訊息
		message = {
			type: 'text',
			text: reply_learn_text
		}

		# 傳送訊息
		line.reply_message(reply_token, message)
	end

	# 傳送 forget 訊息到 line
	def reply_forget(reply_forget_text)
		return nil if reply_forget_text.nil?

		# 取得 reply token
		reply_token = params['events'][0]['replyToken']

		# 設定回覆訊息
		message = {
			type: 'text',
			text: reply_forget_text
		}

		# 傳送訊息
		line.reply_message(reply_token, message)
	end

	# 傳送圖片到 line
	def reply_image_to_line(reply_image)
		return nil if reply_image.nil?

		# 取得 reply token
		reply_token = params['events'][0]['replyToken']

		# 設定回覆圖片
		message = {
			type: "image"
			originalContentUrl: reply_image,
			previewImageUrl: reply_image
		}

		# 傳送圖片
		line.reply_message(reply_token, message)
	end

	# 傳送 教圖片 訊息到 line
	def reply_learn_image(reply_learn_image_text)
		return nil if reply_learn_image_text.nil?

		# 取得 reply token
		reply_token = params['events'][0]['replyToken']

		# 設定回覆訊息
		message = {
			type: 'text',
			text: reply_learn_image_text
		}

		# 傳送訊息
		line.reply_message(reply_token, message)
	end

	# Line Bot API 物件初始化
	def line
		@line ||= Line::Bot::Client.new { |config|
			config.channel_secret = '4c10871ef0bed1cd862ba6ef3a1980d6'
			config.channel_token = 'TJ77RqM5/C707myBu/clmsxNkFfeUThJVJzjVve4CZAJHU/GZ834oYKKA8oxsMMpN6dKAeVsQX2MZ0eIzwMSUhaCxaWGPMpdkwzBbLiUgUGBEaMT0LjXT+OZXGkiccGX+IZqIGXPqUSrGTX5RrQwZgdB04t89/1O/w1cDnyilFU='
		}
	end
end