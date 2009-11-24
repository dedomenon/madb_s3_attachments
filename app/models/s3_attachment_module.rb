require 'S3'
AWS_ACCESS_KEY_ID = AppConfig.aws_access_key_id
AWS_SECRET_ACCESS_KEY = AppConfig.aws_secret_access_key

module FileAttachmentModule
module S3Storage

  def self.included(base)
    base.class_eval do  
	alias_method_chain :save , :s3
  	before_save   :add_s3_key
  	@@base_dir = AppConfig.s3_local_dir
  	@@bucket_name = AppConfig.s3_bucket_name 
    end
    base.extend(ClassMethods)

  end
  def initialize(*args)
    super(*args)
    @s3_conn = S3::AWSAuthConnection.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  end
  def size
     @s3_conn = S3::AWSAuthConnection.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    @s3_conn.head(@@bucket_name, s3_key).http_response.content_length
  end
  
  def download_url
     #debugger
     o = value
     generator = S3::QueryStringAuthGenerator.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
     generator.expires_in = 60
     return generator.get(@@bucket_name, s3_key)
  end


  def save_with_s3
     print "begin save"
     save_without_s3
     o = value
     o[:s3_key] = s3_key
     o[:detail_value_id] = id
     value_will_change!
     value = o
     save_without_s3
     
     make_local_backup

     @attachment.rewind
     @s3_conn = S3::AWSAuthConnection.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
     res = @s3_conn.put(@@bucket_name, s3_key, @attachment.read, { 'Content-Type' => @attachment.content_type, "Content-Length" => @attachment.size.to_s, "Content-Disposition"=> "attachment;filename=\"#{@attachment.original_filename}\"" })
     if res.http_response.code!= "200" or res.http_response.message != "OK"
       #we have a problem
       raise StandardError.new("S3 error. Response code: #{res.http_response.code} and message: #{res.http_response.message}")
     end
      #t = Transfer.new( :detail_value_id => id , :instance => instance, :entity_id => instance.entity_id, :account_id => instance.entity.database.account_id, :user => nil, :size => @attachment.size, :file => @attachment.original_filename, :direction => 'to_server' )
      #t.save
      detail.database.account.increment(:attachment_count).save
  end
  
  
  # *Description*
  # This method is a callback called before saving. It adds
  # the S3 Key 
  def add_s3_key
    o = value
    o[:s3_key] = s3_key
    write_attribute(:value, o)
  end

  # *Description*
  #  Called by the +save_file()+ callback in order to make a local copy
  def make_local_backup
  return true
    @attachment.rewind
    if !FileTest.directory?( local_instance_path )
      FileUtils.mkdir_p( local_instance_path )
    end
    File.open("#{local_instance_path}/#{self.id.to_s}", "w") { |f| f.write(@attachment.read) }
  end
  

  
  
  def destroy
    super
    begin
    @s3_conn ||= S3::AWSAuthConnection.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    @s3_conn.delete(@@bucket_name,s3_key)
    File.delete(local_instance_path+"/"+self.id.to_s)
    rescue Exception => e
      #breakpoint "exeption in destroy"
    end
      detail.database.account.decrement(:attachment_count).save
  end
  
  def instance_prefix
      %Q{#{account_id}/#{database_id}/#{entity_id}/#{instance_id}}
  end

  def s3_key
    %Q{#{instance_prefix}/#{id}}
  end

  def local_instance_path
    %Q{#{@@base_dir}/#{instance_prefix}}
  end

  def send_file_spec
  	{ :method => :redirect, :data => { :url => download_url }}
  end
  


# Class methodes

  module ClassMethods
  end
end
end
