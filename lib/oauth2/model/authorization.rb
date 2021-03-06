module OAuth2
  module Model
    
    class Authorization < ActiveRecord::Base
      # 300 = 5 minutes
      ACCESS_TOKEN_TTL = 300
      self.table_name = :oauth2_authorizations
      
      class << self
        #an method that can be custom defined to determine if authorization is still valid
        # eg. make a remote api call
        # true = still authorized, false = not authorized
        # this is checked for refresh_token grant type
        attr_accessor :authorization_callback
      end
      
      
      belongs_to :oauth2_resource_owner, :polymorphic => true
      alias :owner  :oauth2_resource_owner
      alias :owner= :oauth2_resource_owner=
      
      belongs_to :client, :class_name => 'OAuth2::Model::Client'
      
      validates_presence_of :client, :owner
      
      validates_uniqueness_of :code,               :scope => :client_id, :allow_nil => true
      validates_uniqueness_of :refresh_token_hash, :scope => :client_id, :allow_nil => true
      validates_uniqueness_of :access_token_hash,                        :allow_nil => true
      
      extend Hashing
      hashes_attributes :access_token, :refresh_token
      
      def self.for(resource_owner, client)
        return nil unless resource_owner and client
        resource_owner.oauth2_authorizations.find_by_client_id(client.id)
      end
      
      def self.create_code(client)
        OAuth2.generate_id do |code|
          client.authorizations.count(:conditions => {:code => code}).zero?
        end
      end
      
      def self.create_access_token
        OAuth2.generate_id do |token|
          hash = OAuth2.hashify(token)
          count(:conditions => {:access_token_hash => hash}).zero?
        end
      end
      
      def self.create_refresh_token(client)
        OAuth2.generate_id do |refresh_token|
          hash = OAuth2.hashify(refresh_token)
          client.authorizations.count(:conditions => {:refresh_token_hash => hash}).zero?
        end
      end
      
      def self.for_response_type(response_type, attributes = {})
        instance = self.for(attributes[:owner], attributes[:client]) ||
                   new(:owner => attributes[:owner], :client => attributes[:client])
        
        case response_type
          when CODE
            instance.code ||= create_code(attributes[:client])
          when TOKEN
            instance.access_token  ||= create_access_token
            instance.access_token_expires_at = Time.now + ACCESS_TOKEN_TTL
            instance.refresh_token ||= create_refresh_token(attributes[:client])
          when CODE_AND_TOKEN
            instance.code = create_code(attributes[:client])
            instance.access_token  ||= create_access_token
            instance.access_token_expires_at = Time.now + ACCESS_TOKEN_TTL
            instance.refresh_token ||= create_refresh_token(attributes[:client])
        end
        
        if attributes[:duration]
          instance.expires_at = Time.now + attributes[:duration].to_i
        else
          instance.expires_at = nil
        end
        
        if attributes[:scope]
          scopes = instance.scopes + attributes[:scope].split(/\s+/)
          instance.scope = scopes.join(' ')
        end
        
        instance.save && instance
      end
      
      def exchange!
        self.code          = nil
        self.access_token  = self.class.create_access_token
        self.access_token_expires_at = Time.now + ACCESS_TOKEN_TTL
        self.refresh_token = self.class.create_refresh_token(self.client)
        self.token_type = "Bearer"
        save!
      end
      
      def expired?
        return false unless expires_at
        expires_at < Time.now
      end
      
      def expires_in
        expires_at && (expires_at - Time.now).ceil
      end
      
      def access_token_expired?
        return false unless access_token_expires_at
        access_token_expires_at < Time.now
      end
      
      def access_token_expires_in
        (access_token_expires_at - Time.now).ceil
      end
      
      def generate_code
        self.code ||= self.class.create_code(client)
        save && code
      end
      
      def grants_access?(user, *scopes)
        not expired? and user == owner and in_scope?(scopes)
      end
      
      def in_scope?(request_scope)
        [*request_scope].all?(&scopes.method(:include?))
      end
      
      def scopes
        scope ? scope.split(/\s+/) : []
      end
      

    end
    
  end
end

