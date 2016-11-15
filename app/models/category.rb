class Category < ActiveRecord::Base

  # Default sorting.
  default_scope { order('parent_id ASC, position ASC, name ASC') }

  # Nested set functionality.
  acts_as_nested_set

  # Associations.
  has_and_belongs_to_many   :documents,
                            :order => 'name'

  # Callbacks.
  after_create :get_google_documents

  before_save :set_position
  def set_position
    if self.position.nil?
      max = Category.where(parent_id: self.parent_id).maximum(:position)
      self.position = max.nil? ? 10 : max + 10
    end
  end

  # Validations.
  validates :name,
            presence: true,
            uniqueness: { scope: :parent_id }

  # Scopes.
  scope :top_level, -> { where(parent_id: nil) }

  def move_up
    self.move_position(-15)
  end
  def move_down
    self.move_position(15)
  end
  def move_position(offset)
    self.position += offset
    self.save!
    Category.update_positions(self.parent_id)
  end

  def get_google_documents
    return if self.google_drive_folder.nil?
    begin
      toby = User.find_by_username('toby')
      response = RestClient.get 'https://script.google.com/macros/s/AKfycbz-J-aCcL_RRemvH6gtzWnFeCI9maGFO8ewtVDraNHy4BXa9-k/exec', params: { url: self.google_drive_folder }, accept: :json
      google_documents = JSON.parse(response)
      if google_documents.length > 0
        google_documents.each do |g|
          id = g['id']
          url = g['url']
          exist = self.documents.where(google_id: id)
          if exist.count == 0
            newDoc = Document.new
            newDoc.google_url = url
            newDoc.lookup_google_info
            newDoc.added_by = toby.id
            newDoc.save
            self.documents << newDoc
          end
        end
      end
    rescue => e
      return
    end
  end

  class << self

    def update_positions(parent=nil)

      # Find all categories.
      categories = Category.where(parent_id: parent).order('position ASC, name ASC')

      # Initialize position value.
      current_position = 10

      # Update position of each item.
      categories.each do |c|
        if c.children.length == 0 && c.documents.length == 0
          c.position = 9999999
        else
          c.position = current_position
          current_position += 10
        end
        c.save!
        unless c.children.length == 0
          Category.update_positions(c.id)
        end
      end

    end

  end

end